cmake_minimum_required(VERSION 3.16)
project(mqttrain-plugin VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# Output to build/ directory for install.sh
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/build)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/build)

# Find Qt6
find_package(Qt6 REQUIRED COMPONENTS Core Qml)

# Find libmosquitto
find_library(MOSQUITTO_LIBRARY mosquitto REQUIRED)
if(NOT MOSQUITTO_LIBRARY)
    message(FATAL_ERROR "libmosquitto not found. Install with: sudo pacman -S mosquitto (Arch) or sudo apt install libmosquitto-dev (Debian/Ubuntu)")
endif()

# Plugin sources
set(PLUGIN_SOURCES
    mqttclient.cpp
    mqttclient.h
)

# Build shared library plugin
add_library(mqttrainplugin SHARED ${PLUGIN_SOURCES})

target_link_libraries(mqttrainplugin
    Qt6::Core
    Qt6::Qml
    ${MOSQUITTO_LIBRARY}
)

# Installation
install(TARGETS mqttrainplugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/ObsidianReq/MQTTRain
)

install(FILES qmldir
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/ObsidianReq/MQTTRain
)

message(STATUS "====================================================")
message(STATUS "MQTT Rain C++ Plugin Configuration")
message(STATUS "====================================================")
message(STATUS "Qt6 Qml: ${Qt6Qml_DIR}")
message(STATUS "libmosquitto: ${MOSQUITTO_LIBRARY}")
message(STATUS "Install prefix: ${CMAKE_INSTALL_PREFIX}")
message(STATUS "Output directory: ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
message(STATUS "====================================================")
