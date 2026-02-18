#ifndef MQTTCLIENT_H
#define MQTTCLIENT_H

#include <QObject>
#include <QtMqtt/QMqttClient>
#include <QtMqtt/QMqttSubscription>

class MQTTClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString host READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString username READ username WRITE setUsername NOTIFY usernameChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(QString topic READ topic WRITE setTopic NOTIFY topicChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)

public:
    explicit MQTTClient(QObject *parent = nullptr);
    ~MQTTClient();

    QString host() const { return m_host; }
    void setHost(const QString &host);

    int port() const { return m_port; }
    void setPort(int port);

    QString username() const { return m_username; }
    void setUsername(const QString &username);

    QString password() const { return m_password; }
    void setPassword(const QString &password);

    QString topic() const { return m_topic; }
    void setTopic(const QString &topic);

    bool connected() const;

public slots:
    void connectToHost();
    void disconnectFromHost();

signals:
    void hostChanged();
    void portChanged();
    void usernameChanged();
    void passwordChanged();
    void topicChanged();
    void connectedChanged();
    void messageReceived(const QString &topic, const QString &payload);
    void connectionError(const QString &error);

private slots:
    void onConnected();
    void onDisconnected();
    void onMessageReceived(const QMqttMessage &message);
    void onErrorChanged(QMqttClient::ClientError error);

private:
    QMqttClient *m_client;
    QMqttSubscription *m_subscription;
    QString m_host;
    int m_port;
    QString m_username;
    QString m_password;
    QString m_topic;

    void updateSubscription();
};

#endif // MQTTCLIENT_H
