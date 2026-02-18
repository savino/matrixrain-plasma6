#ifndef MQTTCLIENT_H
#define MQTTCLIENT_H

#include <QObject>
#include <QString>
#include <QTimer>
#include <mosquitto.h>

class MQTTClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY errorChanged)

public:
    explicit MQTTClient(QObject *parent = nullptr);
    ~MQTTClient() override;

    // QML-callable methods
    Q_INVOKABLE void connectToHost(const QString &host,
                                   int port,
                                   const QString &username = QString(),
                                   const QString &password = QString(),
                                   int keepalive = 60);
    Q_INVOKABLE void disconnect();
    Q_INVOKABLE void subscribe(const QString &topic, int qos = 0);
    Q_INVOKABLE void publish(const QString &topic, const QString &payload, int qos = 0, bool retain = false);

    // Properties
    bool isConnected() const { return m_connected; }
    QString lastError() const { return m_lastError; }

signals:
    void connectedChanged();
    void disconnected();
    void messageReceived(const QString &topic, const QString &payload);
    void errorOccurred(const QString &error);
    void errorChanged();
    void subscribed(const QString &topic);
    void debugMessage(const QString &message);

private:
    // libmosquitto callbacks (static)
    static void on_connect_callback(struct mosquitto *mosq, void *obj, int rc);
    static void on_disconnect_callback(struct mosquitto *mosq, void *obj, int rc);
    static void on_message_callback(struct mosquitto *mosq, void *obj, const struct mosquitto_message *message);
    static void on_subscribe_callback(struct mosquitto *mosq, void *obj, int mid, int qos_count, const int *granted_qos);
    static void on_log_callback(struct mosquitto *mosq, void *obj, int level, const char *str);

    // Internal state
    struct mosquitto *m_mosq;
    bool m_connected;
    QString m_lastError;
    QTimer *m_loopTimer;

    void setError(const QString &error);
    void setConnected(bool connected);
};

#endif // MQTTCLIENT_H
