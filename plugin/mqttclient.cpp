#include "mqttclient.h"
#include <QDebug>
#include <QMetaObject>

MQTTClient::MQTTClient(QObject *parent)
    : QObject(parent)
    , m_mosq(nullptr)
    , m_connected(false)
    , m_loopTimer(nullptr)
{
    // Initialize libmosquitto library
    mosquitto_lib_init();

    // Create mosquitto instance
    m_mosq = mosquitto_new(nullptr, true, this);
    if (!m_mosq) {
        setError("Failed to create mosquitto instance");
        return;
    }

    // Set callbacks
    mosquitto_connect_callback_set(m_mosq, on_connect_callback);
    mosquitto_disconnect_callback_set(m_mosq, on_disconnect_callback);
    mosquitto_message_callback_set(m_mosq, on_message_callback);
    mosquitto_subscribe_callback_set(m_mosq, on_subscribe_callback);
    mosquitto_log_callback_set(m_mosq, on_log_callback);

    // Create timer for mosquitto_loop
    m_loopTimer = new QTimer(this);
    m_loopTimer->setInterval(10); // 10ms for responsive event handling
    connect(m_loopTimer, &QTimer::timeout, this, [this]() {
        if (m_mosq) {
            int rc = mosquitto_loop(m_mosq, 0, 1); // Non-blocking
            if (rc != MOSQ_ERR_SUCCESS && rc != MOSQ_ERR_NO_CONN) {
                setError(QString("Loop error: %1").arg(mosquitto_strerror(rc)));
            }
        }
    });
}

MQTTClient::~MQTTClient()
{
    disconnect();
    if (m_mosq) {
        mosquitto_destroy(m_mosq);
    }
    mosquitto_lib_cleanup();
}

void MQTTClient::connectToHost(const QString &host, int port,
                               const QString &username, const QString &password,
                               int keepalive)
{
    if (!m_mosq) {
        setError("Mosquitto instance not initialized");
        return;
    }

    // Set authentication if provided
    if (!username.isEmpty()) {
        mosquitto_username_pw_set(m_mosq,
                                  username.toUtf8().constData(),
                                  password.isEmpty() ? nullptr : password.toUtf8().constData());
    }

    // Connect to broker
    int rc = mosquitto_connect(m_mosq,
                               host.toUtf8().constData(),
                               port,
                               keepalive);

    if (rc != MOSQ_ERR_SUCCESS) {
        setError(QString("Connect failed: %1").arg(mosquitto_strerror(rc)));
        return;
    }

    // Start event loop
    m_loopTimer->start();

    emit debugMessage(QString("Connecting to %1:%2...").arg(host).arg(port));
}

void MQTTClient::disconnect()
{
    if (m_loopTimer) {
        m_loopTimer->stop();
    }

    if (m_mosq && m_connected) {
        mosquitto_disconnect(m_mosq);
        setConnected(false);
    }
}

void MQTTClient::subscribe(const QString &topic, int qos)
{
    if (!m_mosq || !m_connected) {
        setError("Not connected to broker");
        return;
    }

    int rc = mosquitto_subscribe(m_mosq, nullptr, topic.toUtf8().constData(), qos);
    if (rc != MOSQ_ERR_SUCCESS) {
        setError(QString("Subscribe failed: %1").arg(mosquitto_strerror(rc)));
    } else {
        emit debugMessage(QString("Subscribing to: %1").arg(topic));
    }
}

void MQTTClient::publish(const QString &topic, const QString &payload, int qos, bool retain)
{
    if (!m_mosq || !m_connected) {
        setError("Not connected to broker");
        return;
    }

    QByteArray data = payload.toUtf8();
    int rc = mosquitto_publish(m_mosq, nullptr,
                               topic.toUtf8().constData(),
                               data.size(),
                               data.constData(),
                               qos,
                               retain);

    if (rc != MOSQ_ERR_SUCCESS) {
        setError(QString("Publish failed: %1").arg(mosquitto_strerror(rc)));
    }
}

// Callbacks
void MQTTClient::on_connect_callback(struct mosquitto *mosq, void *obj, int rc)
{
    Q_UNUSED(mosq)
    MQTTClient *client = static_cast<MQTTClient*>(obj);

    if (rc == 0) {
        QMetaObject::invokeMethod(client, [client]() {
            client->setConnected(true);
            client->setError("");
            emit client->debugMessage("✅ Connected to MQTT broker");
        }, Qt::QueuedConnection);
    } else {
        QMetaObject::invokeMethod(client, [client, rc]() {
            client->setError(QString("Connection failed: %1").arg(mosquitto_connack_string(rc)));
        }, Qt::QueuedConnection);
    }
}

void MQTTClient::on_disconnect_callback(struct mosquitto *mosq, void *obj, int rc)
{
    Q_UNUSED(mosq)
    MQTTClient *client = static_cast<MQTTClient*>(obj);

    QMetaObject::invokeMethod(client, [client, rc]() {
        client->setConnected(false);
        if (rc != 0) {
            client->setError(QString("Unexpected disconnect: %1").arg(rc));
        }
        emit client->disconnected();
        emit client->debugMessage(QString("❌ Disconnected (rc=%1)").arg(rc));
    }, Qt::QueuedConnection);
}

void MQTTClient::on_message_callback(struct mosquitto *mosq, void *obj,
                                     const struct mosquitto_message *message)
{
    Q_UNUSED(mosq)
    MQTTClient *client = static_cast<MQTTClient*>(obj);

    QString topic = QString::fromUtf8(message->topic);
    QString payload = QString::fromUtf8(static_cast<const char*>(message->payload), message->payloadlen);

    QMetaObject::invokeMethod(client, [client, topic, payload]() {
        emit client->messageReceived(topic, payload);
        emit client->debugMessage(QString("📨 [%1] %2").arg(topic, payload.left(80)));
    }, Qt::QueuedConnection);
}

void MQTTClient::on_subscribe_callback(struct mosquitto *mosq, void *obj,
                                       int mid, int qos_count, const int *granted_qos)
{
    Q_UNUSED(mosq)
    Q_UNUSED(mid)
    Q_UNUSED(qos_count)
    Q_UNUSED(granted_qos)
    MQTTClient *client = static_cast<MQTTClient*>(obj);

    QMetaObject::invokeMethod(client, [client]() {
        emit client->debugMessage("✅ Subscribed successfully");
    }, Qt::QueuedConnection);
}

void MQTTClient::on_log_callback(struct mosquitto *mosq, void *obj, int level, const char *str)
{
    Q_UNUSED(mosq)
    Q_UNUSED(level)
    MQTTClient *client = static_cast<MQTTClient*>(obj);

    QMetaObject::invokeMethod(client, [client, str]() {
        emit client->debugMessage(QString("[libmosquitto] %1").arg(str));
    }, Qt::QueuedConnection);
}

// Internal helpers
void MQTTClient::setError(const QString &error)
{
    if (m_lastError != error) {
        m_lastError = error;
        emit errorChanged();
        if (!error.isEmpty()) {
            emit errorOccurred(error);
        }
    }
}

void MQTTClient::setConnected(bool connected)
{
    if (m_connected != connected) {
        m_connected = connected;
        emit connectedChanged();
    }
}
