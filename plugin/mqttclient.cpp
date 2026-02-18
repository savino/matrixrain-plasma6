#include "mqttclient.h"
#include <QDebug>
#include <QTcpSocket>

MQTTClient::MQTTClient(QObject *parent)
    : QObject(parent)
    , m_client(new QMqttClient(this))
    , m_subscription(nullptr)
    , m_port(1883)
{
    // Connect signals
    connect(m_client, &QMqttClient::connected, this, &MQTTClient::onConnected);
    connect(m_client, &QMqttClient::disconnected, this, &MQTTClient::onDisconnected);
    connect(m_client, &QMqttClient::errorChanged, this, &MQTTClient::onErrorChanged);
    connect(m_client, &QMqttClient::stateChanged, this, [this](QMqttClient::ClientState state) {
        qDebug() << "MQTT Client state changed:" << state;
    });
    
    qDebug() << "MQTTClient initialized, Qt version:" << qVersion();
}

MQTTClient::~MQTTClient()
{
    if (m_client->state() == QMqttClient::Connected) {
        m_client->disconnectFromHost();
    }
}

void MQTTClient::setHost(const QString &host)
{
    if (m_host != host) {
        qDebug() << "Setting host:" << host;
        m_host = host;
        m_client->setHostname(host);
        emit hostChanged();
    }
}

void MQTTClient::setPort(int port)
{
    if (m_port != port) {
        qDebug() << "Setting port:" << port;
        m_port = port;
        m_client->setPort(static_cast<quint16>(port));
        emit portChanged();
    }
}

void MQTTClient::setUsername(const QString &username)
{
    if (m_username != username) {
        qDebug() << "Setting username:" << username;
        m_username = username;
        m_client->setUsername(username);
        emit usernameChanged();
    }
}

void MQTTClient::setPassword(const QString &password)
{
    if (m_password != password) {
        qDebug() << "Setting password: [" << (password.isEmpty() ? "empty" : "set") << "]";
        m_password = password;
        m_client->setPassword(password);
        emit passwordChanged();
    }
}

void MQTTClient::setTopic(const QString &topic)
{
    if (m_topic != topic) {
        qDebug() << "Setting topic:" << topic;
        m_topic = topic;
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
        qWarning() << "Cannot connect: Host is empty";
        emit connectionError("Host is empty");
        return;
    }

    qDebug() << "========================================";
    qDebug() << "Attempting MQTT connection:";
    qDebug() << "  Host:" << m_host;
    qDebug() << "  Port:" << m_port;
    qDebug() << "  Username:" << (m_username.isEmpty() ? "(none)" : m_username);
    qDebug() << "  Password:" << (m_password.isEmpty() ? "(none)" : "[set]");
    qDebug() << "  Topic:" << m_topic;
    qDebug() << "  Current client state:" << m_client->state();
    
    // Check if already connected or connecting
    if (m_client->state() == QMqttClient::Connected) {
        qDebug() << "Already connected, disconnecting first...";
        m_client->disconnectFromHost();
        // Wait for disconnection (synchronous approach)
        QEventLoop loop;
        connect(m_client, &QMqttClient::disconnected, &loop, &QEventLoop::quit);
        QTimer::singleShot(1000, &loop, &QEventLoop::quit); // timeout
        loop.exec();
    }
    
    // Create fresh transport
    qDebug() << "Creating new QTcpSocket transport...";
    auto *transport = new QTcpSocket(m_client);
    
    // Debug socket
    qDebug() << "Socket created, state:" << transport->state();
    
    // Set transport
    qDebug() << "Setting transport on QMqttClient...";
    m_client->setTransport(transport, QMqttClient::IODevice);
    
    qDebug() << "Client state after setTransport:" << m_client->state();
    qDebug() << "Calling connectToHost()...";
    
    m_client->connectToHost();
    
    qDebug() << "connectToHost() returned, client state:" << m_client->state();
    qDebug() << "========================================";
}

void MQTTClient::disconnectFromHost()
{
    qDebug() << "Disconnecting from MQTT broker...";
    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }
    m_client->disconnectFromHost();
}

void MQTTClient::onConnected()
{
    qDebug() << "✅ Successfully connected to MQTT broker";
    emit connectedChanged();
    updateSubscription();
}

void MQTTClient::onDisconnected()
{
    qDebug() << "❌ Disconnected from MQTT broker";
    if (m_subscription) {
        m_subscription = nullptr;
    }
    emit connectedChanged();
}

void MQTTClient::onMessageReceived(const QMqttMessage &message)
{
    QString topic = message.topic().name();
    QString payload = QString::fromUtf8(message.payload());
    
    qDebug() << "📨 MQTT message - Topic:" << topic << "Payload length:" << payload.length();
    emit messageReceived(topic, payload);
}

void MQTTClient::onErrorChanged(QMqttClient::ClientError error)
{
    if (error == QMqttClient::NoError)
        return;

    QString errorString;
    switch (error) {
        case QMqttClient::InvalidProtocolVersion:
            errorString = "Invalid protocol version";
            break;
        case QMqttClient::IdRejected:
            errorString = "Client ID rejected";
            break;
        case QMqttClient::ServerUnavailable:
            errorString = "Server unavailable";
            break;
        case QMqttClient::BadUsernameOrPassword:
            errorString = "Bad username or password";
            break;
        case QMqttClient::NotAuthorized:
            errorString = "Not authorized";
            break;
        case QMqttClient::TransportInvalid:
            errorString = "Transport invalid";
            qWarning() << "🔴 TRANSPORT INVALID ERROR - This means QMqttClient's transport is null or invalid";
            qWarning() << "   Client state:" << m_client->state();
            qWarning() << "   Protocol version:" << m_client->protocolVersion();
            break;
        case QMqttClient::ProtocolViolation:
            errorString = "Protocol violation";
            break;
        case QMqttClient::UnknownError:
        default:
            errorString = "Unknown error";
            break;
    }

    qWarning() << "⚠️ MQTT Error:" << errorString;
    emit connectionError(errorString);
}

void MQTTClient::updateSubscription()
{
    if (!connected() || m_topic.isEmpty())
        return;

    // Unsubscribe from previous topic
    if (m_subscription) {
        m_subscription->unsubscribe();
        m_subscription = nullptr;
    }

    // Subscribe to new topic
    qDebug() << "📡 Subscribing to topic:" << m_topic;
    m_subscription = m_client->subscribe(m_topic, 0); // QoS 0

    if (m_subscription) {
        connect(m_subscription, &QMqttSubscription::messageReceived,
                this, &MQTTClient::onMessageReceived);
        qDebug() << "✅ Successfully subscribed";
    } else {
        qWarning() << "❌ Failed to subscribe to topic:" << m_topic;
    }
}
