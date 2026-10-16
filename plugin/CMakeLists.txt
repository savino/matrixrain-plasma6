cmake_minimum_required(VERSION 3.16)
project(mqttrain-plugin VERSION 1.0.0 LANGUAGES CXX)

include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

set(QT_QML_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/qt6/qml" CACHE STRING
    "Qt 6 QML import directory")

# Find Qt6 modules
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Mqtt)

if(NOT Qt6Mqtt_FOUND)
    message(FATAL_ERROR "
════════════════════════════════════════════════════════════
  Qt6 Mqtt module not found!
  
  Install with:
  • Arch/Manjaro:  sudo pacman -S qt6-mqtt
  • Ubuntu/Debian: sudo apt install libqt6mqtt6-dev
  • Fedora:        sudo dnf install qt6-qtmqtt-devel
════════════════════════════════════════════════════════════
    ")
endif()

# Plugin sources
set(PLUGIN_SOURCES
    plugin.cpp
    mqttclient.cpp
    mqttclient.h
)

# Build shared library plugin
add_library(mqttrainplugin SHARED ${PLUGIN_SOURCES})

target_link_libraries(mqttrainplugin
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Mqtt
)

# Installation
install(TARGETS mqttrainplugin
    LIBRARY DESTINATION "${QT_QML_INSTALL_DIR}/ObsidianReq/MQTTRain"
    COMPONENT Plugin
)

install(FILES qmldir
    DESTINATION "${QT_QML_INSTALL_DIR}/ObsidianReq/MQTTRain"
    COMPONENT Plugin
)

install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../package/"
    DESTINATION "${CMAKE_INSTALL_DATADIR}/plasma/wallpapers/obsidianreq.plasma.wallpaper.mqttrain"
    COMPONENT Wallpaper
)

message(STATUS "====================================================")
message(STATUS "MQTT Rain C++ Plugin Configuration")
message(STATUS "====================================================")
message(STATUS "Qt6 Core:  ${Qt6Core_DIR}")
message(STATUS "Qt6 Gui:   ${Qt6Gui_DIR}")
message(STATUS "Qt6 Qml:   ${Qt6Qml_DIR}")
message(STATUS "Qt6 Mqtt:  ${Qt6Mqtt_DIR}")
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "Qt QML install directory: ${QT_QML_INSTALL_DIR}")
message(STATUS "====================================================")
