# Copilot Instructions for Matrix-style Wallpaper for KDE Plasma 6

## Overview
This project provides a Matrix-style "code rainfall" wallpaper for KDE Plasma 6. It allows users to customize various aspects of the wallpaper, including font size, color modes, speed, jitter effects, and glitch chances.

## Architecture
- **Main Components**: The primary components include `main.qml` for the wallpaper logic, `config.qml` for user configuration, and `main.xml` for storing configuration settings.
- **Data Flow**: Configuration values are passed from `config.qml` to `main.qml`, affecting how the wallpaper is rendered. The `Canvas` in `main.qml` handles the drawing of the falling characters based on these configurations.

## Developer Workflows
- **Installation**: Use the `install.sh` script to install the wallpaper package using `kpackagetool6`. Ensure that `kpackagetool6` is installed on your system.
- **Building**: The project does not have a traditional build process; it relies on the installation script to set up the wallpaper.
- **Testing**: To test changes, modify the QML files and restart the Plasma shell using `kquitapp6 plasmashell && kstart plasmashell`.

## Project Conventions
- **Configuration Management**: Configuration values are stored in `main.xml` and accessed via properties in QML files. Use `property alias` to bind UI elements to configuration values.
- **Color Modes**: The wallpaper supports two color modes: single color and multi-color palettes. The selected mode affects how characters are rendered on the screen.

## Integration Points
- **External Dependencies**: The project depends on `kpackagetool6` for installation and requires KDE Plasma 6.
- **Cross-Component Communication**: Configuration changes in `config.qml` directly influence the rendering logic in `main.qml`. Ensure that any changes to configuration properties are reflected in the UI and the rendering logic.

## Examples
- To change the font size, modify the `fontSize` property in `config.qml` and observe the changes in `main.qml`.
- The `Canvas` in `main.qml` uses a timer to control the speed of the falling characters, which can be adjusted via the `speed` property.

## Conclusion
These instructions should help AI coding agents understand the structure and workflows of the Matrix-style wallpaper project, enabling them to assist effectively in development and maintenance tasks.