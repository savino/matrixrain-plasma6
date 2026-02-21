#pragma once
#include <QObject>
#include <QMqttClient>
#include <QMqttSubscription>
#include <QTcpSocket>
#include <QTimer>

class MQTTClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString host     READ host     WRITE setHost     NOTIFY hostChanged)
    Q_PROPERTY(int     port     READ port     WRITE setPort     NOTIFY portChanged)
    Q_PROPERTY(QString username READ username WRITE setUsername NOTIFY usernameChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(QString topic    READ topic    WRITE setTopic    NOTIFY topicChanged)
    Q_PROPERTY(bool    connected READ connected               NOTIFY connectedChanged)
    Q_PROPERTY(int     reconnectInterval READ reconnectInterval WRITE setReconnectInterval NOTIFY reconnectIntervalChanged)

public:
    explicit MQTTClient(QObject *parent = nullptr);
    ~MQTTClient();

    QString host()     const { return m_host; }
    int     port()     const { return m_port; }
    QString username() const { return m_username; }
    QString password() const { return m_password; }
    QString topic()    const { return m_topic; }
    bool    connected() const;
    int     reconnectInterval() const { return m_reconnectInterval; }

public slots:
    void setHost(const QString &host);
    void setPort(int port);
    void setUsername(const QString &username);
    void setPassword(const QString &password);
    void setTopic(const QString &topic);
    void setReconnectInterval(int interval);
    void connectToHost();
    void disconnectFromHost();

signals:
    void hostChanged();
    void portChanged();
    void usernameChanged();
    void passwordChanged();
    void topicChanged();
    void connectedChanged();
    void reconnectIntervalChanged();
    void reconnecting();
    void messageReceived(const QString &topic, const QString &payload);
    void connectionError(const QString &error);

private slots:
    void onConnected();
    void onDisconnected();
    void onMessageReceived(const QMqttMessage &message);
    void onErrorChanged(QMqttClient::ClientError error);
    void attemptReconnect();

private:
    void updateSubscription();

    QMqttClient       *m_client;
    QMqttSubscription *m_subscription;
    QTimer            *m_connackTimer;
    QTimer            *m_reconnectTimer;
    QTcpSocket        *m_socket;
    QString            m_host;
    int                m_port;
    QString            m_username;
    QString            m_password;
    QString            m_topic;
    int                m_reconnectInterval;
    bool               m_shouldBeConnected;
};
