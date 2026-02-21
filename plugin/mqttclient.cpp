#include "mqttclient.h"
#include <QDebug>
#include <QTcpSocket>
#include <QTimer>

MQTTClient::MQTTClient(QObject *parent)
    : QObject(parent)
    , m_client(new QMqttClient(this))
    , m_subscription(nullptr)
    , m_port(1883)
    , m_connackTimer(new QTimer(this))
    , m_reconnectTimer(new QTimer(this))
    , m_socket(nullptr)
    , m_reconnectInterval(30000)
    , m_shouldBeConnected(false)
{
    connect(m_client, &QMqttClient::connected,    this, &MQTTClient::onConnected);
    connect(m_client, &QMqttClient::disconnected, this, &MQTTClient::onDisconnected);
    connect(m_client, &QMqttClient::errorChanged, this, &MQTTClient::onErrorChanged);
    connect(m_client, &QMqttClient::stateChanged, this, [](QMqttClient::ClientState s) {
        qDebug() << "\xf0\x9f\x93\x8a MQTT state:" << s;
    });

    m_connackTimer->setSingleShot(true);
    m_connackTimer->setInterval(5000);
    connect(m_connackTimer, &QTimer::timeout, this, [this]() {
        qWarning() << "\xe2\x8f\xb0 CONNACK timeout!";
        emit connectionError("CONNACK timeout");
        // Preserve reconnect intent: disconnectFromHost() sets m_shouldBeConnected=false,
        // so we save and restore the flag to keep reconnection scheduled.
        bool wasConnecting = m_shouldBeConnected;
        disconnectFromHost();
        if (wasConnecting) {
            m_shouldBeConnected = true;
            qDebug() << "\xf0\x9f\x94\x84 CONNACK timeout, scheduling reconnection in" << m_reconnectInterval << "ms...";
            m_reconnectTimer->start();
        }
    });

    // Configurazione timer di riconnessione
    m_reconnectTimer->setSingleShot(true);
    m_reconnectTimer->setInterval(m_reconnectInterval);
    connect(m_reconnectTimer, &QTimer::timeout, this, &MQTTClient::attemptReconnect);

    qDebug() << "MQTTClient initialized, Qt:" << qVersion();
}

MQTTClient::~MQTTClient()
{
    disconnectFromHost();
}

void MQTTClient::setHost(const QString &host)
{
    QString v = host.trimmed();
    if (m_host != v) {
        qDebug() << "setHost:" << v;
        m_host = v;
        m_client->setHostname(v);
        emit hostChanged();
    }
}

void MQTTClient::setPort(int port)
{
    if (m_port != port) {
        qDebug() << "setPort:" << port;
        m_port = port;
        m_client->setPort(static_cast<quint16>(port));
        emit portChanged();
    }
}

void MQTTClient::setUsername(const QString &username)
{
    QString v = username.trimmed();
    if (m_username != v) {
        qDebug() << "setUsername:" << v;
        m_username = v;
        m_client->setUsername(v);
        emit usernameChanged();
    }
}

void MQTTClient::setPassword(const QString &password)
{
    if (m_password != password) {
        m_password = password;
        m_client->setPassword(password);
        emit passwordChanged();
    }
}

void MQTTClient::setTopic(const QString &topic)
{
    QString v = topic.trimmed();
    if (m_topic != v) {
        qDebug() << "setTopic: [" << v << "]";
        m_topic = v;
        emit topicChanged();
        updateSubscription();
    }
}

void MQTTClient::setReconnectInterval(int interval)
{
    if (m_reconnectInterval != interval) {
        qDebug() << "setReconnectInterval:" << interval << "ms";
        m_reconnectInterval = interval;
        m_reconnectTimer->setInterval(interval);
        emit reconnectIntervalChanged();
    }
}

bool MQTTClient::connected() const
{
    return m_client->state() == QMqttClient::Connected;
}

void MQTTClient::connectToHost()
{
    if (m_host.isEmpty()) {
        qWarning() << "Cannot connect: host is empty";
        emit connectionError("Host is empty");
        return;
    }

    m_shouldBeConnected = true;
    m_reconnectTimer->stop();

    qDebug() << "==== connectToHost ==== host:" << m_host << "port:" << m_port << "user:" << m_username;

    if (m_socket) {
        m_socket->disconnect();
        m_socket->abort();
        m_socket->deleteLater();
        m_socket = nullptr;
    }

    m_socket = new QTcpSocket(this);

    connect(m_socket, &QTcpSocket::stateChanged, [](QAbstractSocket::SocketState s) {
        qDebug() << "\xf0\x9f\x94\x84 TCP:" << s;
    });
    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::errorOccurred),
            this, [this](QAbstractSocket::SocketError e) {
        qWarning() << "\xf0\x9f\x94\xb4 TCP error:" << e << m_socket->errorString();
        emit connectionError("TCP: " + m_socket->errorString());
    });

    // Once TCP connects, attach as IODevice and send MQTT CONNECT
    connect(m_socket, &QTcpSocket::connected, this, [this]() {
        qDebug() << "\xe2\x9c\x85 TCP connected \xe2\x80\x94 attaching IODevice transport";
        m_client->setHostname(m_host);
        m_client->setPort(static_cast<quint16>(m_port));
        m_client->setUsername(m_username);
        m_client->setPassword(m_password);
        m_client->setTransport(m_socket, QMqttClient::IODevice);
        m_connackTimer->start();
        m_client->connectToHost();
        qDebug() << "  MQTT state:" << m_client->state();
    });

    qDebug() << "  Connecting TCP...";
    m_socket->connectToHost(m_host, static_cast<quint16>(m_port));
}

void MQTTClient::disconnectFromHost()
{
    m_shouldBeConnected = false;
    m_reconnectTimer->stop();
    m_connackTimer->stop();

    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }
    m_client->disconnectFromHost();
    if (m_socket)
        m_socket->abort();
}

void MQTTClient::onConnected()
{
    m_connackTimer->stop();
    qDebug() << "\xf0\x9f\x8e\x89 MQTT connected!";
    emit connectedChanged();
    updateSubscription();
}

void MQTTClient::onDisconnected()
{
    m_connackTimer->stop();
    qDebug() << "\xe2\x9d\x8c MQTT disconnected";

    if (m_subscription)
        m_subscription = nullptr;

    emit connectedChanged();

    // Avvia tentativi di riconnessione se necessario
    if (m_shouldBeConnected) {
        qDebug() << "\xf0\x9f\x94\x84 Scheduling reconnection attempt in" << m_reconnectInterval << "ms...";
        m_reconnectTimer->start();
    }
}

void MQTTClient::onMessageReceived(const QMqttMessage &message)
{
    emit messageReceived(message.topic().name(),
                         QString::fromUtf8(message.payload()));
}

void MQTTClient::onErrorChanged(QMqttClient::ClientError error)
{
    if (error == QMqttClient::NoError) return;

    static const QMap<QMqttClient::ClientError, QString> errors = {
        { QMqttClient::InvalidProtocolVersion, "Invalid protocol version" },
        { QMqttClient::IdRejected,             "Client ID rejected" },
        { QMqttClient::ServerUnavailable,      "Server unavailable" },
        { QMqttClient::BadUsernameOrPassword,  "Bad username or password" },
        { QMqttClient::NotAuthorized,          "Not authorized" },
        { QMqttClient::TransportInvalid,       "Transport invalid" },
        { QMqttClient::ProtocolViolation,      "Protocol violation" },
    };

    QString msg = errors.value(error, "Unknown error");
    qWarning() << "\xe2\x9a\xa0\xef\xb8\x8f MQTT Error:" << msg;
    emit connectionError(msg);

    // Avvia riconnessione per errori non legati a credenziali
    if (m_shouldBeConnected &&
        error != QMqttClient::BadUsernameOrPassword &&
        error != QMqttClient::NotAuthorized) {
        qDebug() << "\xf0\x9f\x94\x84 Error detected, scheduling reconnection attempt in" << m_reconnectInterval << "ms...";
        m_reconnectTimer->start();
    }
}

void MQTTClient::attemptReconnect()
{
    if (!m_shouldBeConnected) {
        qDebug() << "\xe2\x8f\xb8\xef\xb8\x8f Reconnection canceled (shouldBeConnected=false)";
        return;
    }

    if (connected()) {
        qDebug() << "\xe2\x9c\x85 Already connected, skipping reconnection";
        return;
    }

    qDebug() << "\xf0\x9f\x94\x84 Attempting reconnection to" << m_host << ":" << m_port;
    emit reconnecting();
    connectToHost();
}

void MQTTClient::updateSubscription()
{
    if (!connected() || m_topic.isEmpty()) return;

    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }

    qDebug() << "\xf0\x9f\x93\xa1 subscribing to:" << m_topic;
    m_subscription = m_client->subscribe(m_topic, 0);

    if (m_subscription) {
        connect(m_subscription, &QMqttSubscription::messageReceived,
                this, &MQTTClient::onMessageReceived);
        qDebug() << "\xe2\x9c\x85 subscribed";
    } else {
        qWarning() << "\xe2\x9d\x8c subscribe failed:" << m_topic;
    }
}
