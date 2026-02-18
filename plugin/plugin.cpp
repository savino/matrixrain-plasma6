#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include "mqttclient.h"

class MQTTRainPlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        Q_ASSERT(uri == QLatin1String("ObsidianReq.MQTTRain"));
        qmlRegisterType<MQTTClient>(uri, 1, 0, "MQTTClient");
    }
};

#include "plugin.moc"
