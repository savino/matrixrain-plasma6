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
    , m_socket(nullptr)
{
    connect(m_client, &QMqttClient::connected,    this, &MQTTClient::onConnected);
    connect(m_client, &QMqttClient::disconnected, this, &MQTTClient::onDisconnected);
    connect(m_client, &QMqttClient::errorChanged, this, &MQTTClient::onErrorChanged);
    connect(m_client, &QMqttClient::stateChanged, this, [](QMqttClient::ClientState s) {
        qDebug() << "📊 MQTT state:" << s;
    });

    m_connackTimer->setSingleShot(true);
    m_connackTimer->setInterval(5000);
    connect(m_connackTimer, &QTimer::timeout, this, [this]() {
        qWarning() << "⏰ CONNACK timeout!";
        emit connectionError("CONNACK timeout");
        disconnectFromHost();
    });

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
        qDebug() << "setPassword: [" << (password.isEmpty() ? "empty" : "set") << "]";
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

    qDebug() << "==== connectToHost ====";
    qDebug() << "  host:"  << m_host;
    qDebug() << "  port:"  << m_port;
    qDebug() << "  user:"  << m_username;
    qDebug() << "  topic:" << m_topic;

    // Clean up previous socket
    if (m_socket) {
        m_socket->disconnect();
        m_socket->abort();
        m_socket->deleteLater();
        m_socket = nullptr;
    }

    // Step 1: Create socket and connect TCP manually
    m_socket = new QTcpSocket(this);

    connect(m_socket, &QTcpSocket::stateChanged, [](QAbstractSocket::SocketState s) {
        qDebug() << "🔄 TCP state:" << s;
    });

    connect(m_socket, QOverload<QAbstractSocket::SocketError>::of(&QTcpSocket::errorOccurred),
            this, [this](QAbstractSocket::SocketError e) {
        qWarning() << "🔴 TCP error:" << e << m_socket->errorString();
        emit connectionError("TCP: " + m_socket->errorString());
    });

    connect(m_socket, &QTcpSocket::bytesWritten, [](qint64 bytes) {
        qDebug() << "↑ Bytes written to broker:" << bytes;
    });

    connect(m_socket, &QTcpSocket::readyRead, [this]() {
        QByteArray data = m_socket->peek(m_socket->bytesAvailable());
        qDebug() << "↓ Broker raw reply (" << data.size() << "bytes):" << data.toHex();
    });

    // Step 2: Once TCP connects, attach as IODevice and send MQTT CONNECT
    connect(m_socket, &QTcpSocket::connected, this, [this]() {
        qDebug() << "✅ TCP connected! Setting IODevice transport and sending MQTT CONNECT...";

        // Set MQTT parameters
        m_client->setHostname(m_host);
        m_client->setPort(static_cast<quint16>(m_port));
        m_client->setUsername(m_username);
        m_client->setPassword(m_password);

        // Use pre-connected socket as IODevice
        // QMqttClient will immediately send MQTT CONNECT packet
        m_client->setTransport(m_socket, QMqttClient::IODevice);

        m_connackTimer->start();
        m_client->connectToHost();

        qDebug() << "  MQTT state after connectToHost():" << m_client->state();
    });

    qDebug() << "  Connecting TCP to" << m_host << ":" << m_port;
    m_socket->connectToHost(m_host, static_cast<quint16>(m_port));
    qDebug() << "======================";
}

void MQTTClient::disconnectFromHost()
{
    m_connackTimer->stop();
    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }
    m_client->disconnectFromHost();
    if (m_socket) {
        m_socket->abort();
    }
}

void MQTTClient::onConnected()
{
    m_connackTimer->stop();
    qDebug() << "🎉 MQTT connected!";
    emit connectedChanged();
    updateSubscription();
}

void MQTTClient::onDisconnected()
{
    m_connackTimer->stop();
    qDebug() << "❌ MQTT disconnected";
    if (m_subscription) m_subscription = nullptr;
    emit connectedChanged();
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
    qWarning() << "⚠️ MQTT Error:" << msg;
    emit connectionError(msg);
}

void MQTTClient::updateSubscription()
{
    if (!connected() || m_topic.isEmpty()) return;

    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }

    qDebug() << "📡 subscribing to:" << m_topic;
    m_subscription = m_client->subscribe(m_topic, 0);

    if (m_subscription) {
        connect(m_subscription, &QMqttSubscription::messageReceived,
                this, &MQTTClient::onMessageReceived);
        qDebug() << "✅ subscribed";
    } else {
        qWarning() << "❌ subscribe failed:" << m_topic;
    }
}
