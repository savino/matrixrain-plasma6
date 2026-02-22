# Changelog

All notable changes to MatrixRain Plasma6 Wallpaper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- **Horizontal Inline Renderer (Mode 3)** — "Matrix Inject" rendering mode
  - MQTT message characters injected directly into rain grid
  - No background boxes — messages appear as part of the Matrix rain
  - Two-pass rendering: `renderColumnContent` + `renderInlineChars`
  - FIFO queue with capacity 15 messages (up from 5)
  - AABB collision detection with 12 placement attempts
  - Messages fade naturally after expiry (3s default)
  - Performance: max 180 fillText/frame, O(15) collision checks per column

### Changed
- `MatrixCanvas.qml`: rendering pipeline now calls `renderInlineChars()` (Step 3) instead of `renderOverlay()`
- `main.qml`: render mode 3 now instantiates `HorizontalInlineRenderer` instead of legacy overlay
- `config.qml`: ComboBox label updated to "Horizontal Inline (Matrix Inject)"
- Documentation: comprehensive renderer specs added to `docs/mqtt-specs.md` (§6)

### Removed
- **HorizontalOverlayRenderer.qml** (legacy implementation with background boxes)
  - Replaced by superior `HorizontalInlineRenderer.qml`
  - Old implementation had:
    - Visible black background boxes (broke Matrix aesthetic)
    - `renderOverlay()` function (incompatible with new pipeline)
    - Max 5 messages capacity (insufficient for high-traffic MQTT)
    - Static cell occupation map (memory inefficient)

### Fixed
- Render mode 3 now correctly displays inline messages without background artifacts
- MQTT messages no longer appear as separate UI widgets
- Drop head collision detection prevents Katakana chars from overwriting MQTT text

---

## Migration Notes

### For users upgrading from previous versions:

**What changed:**
- When you select **"Horizontal Inline (Matrix Inject)"** in the settings, messages now blend seamlessly into the rain
- No more black boxes around MQTT text
- You can have up to 15 messages visible simultaneously (vs 5 before)

**Recommended actions:**
1. Pull latest changes: `git pull origin main`
2. Reinstall wallpaper: `kpackagetool6 --type=Plasma/Wallpaper --upgrade package/`
3. Restart Plasma: `plasmashell --replace &`
4. Open wallpaper settings → MQTT & Network → Render Mode
5. Select **"Horizontal Inline (Matrix Inject)"**

**If you see old behavior (black boxes):**
- Your Plasma session is caching old code
- Force full restart:
  ```bash
  killall plasmashell
  kquitapp6 plasmashell
  plasmashell &
  ```

### For developers extending the renderer:

**New renderer interface (as of this release):**

```qml
// Required functions:
function initializeColumns(numColumns)
function renderColumnContent(ctx, columnIndex, x, y, drops)
function onColumnWrap(columnIndex)

// Optional functions:
function renderInlineChars(ctx)  // Called AFTER rain loop (Step 3)

// Required properties (set by MatrixCanvas):
property int canvasWidth
property int canvasHeight
property real fadeStrength
property real jitter
```

**Breaking changes:**
- `renderOverlay(ctx)` is **deprecated** — use `renderInlineChars(ctx)` instead
- `HorizontalOverlayRenderer` class removed — use `HorizontalInlineRenderer`
- If your custom renderer used overlay boxes, migrate to inline grid injection

**Coordinate system (unchanged):**
```javascript
gridCol = Math.floor(pixelX / fontSize)
gridRow = Math.floor(pixelY / fontSize)
pixelX  = gridCol * fontSize
pixelY  = (gridRow + 1) * fontSize   // baseline for alphabetic text
```

---

## [Previous Releases]

### v0.9.x — Pre-inline era
- Initial MQTT integration
- Modes 0-2: Classic, Mixed, MQTT-Only, MQTT-Driven
- Legacy Horizontal Overlay (mode 3) with background boxes

---

## Links

- [Repository](https://github.com/savino/matrixrain-plasma6)
- [Renderer Documentation](docs/mqtt-specs.md#6-modalit%C3%A0-di-rendering-mqtt-renderers)
- [Architecture Overview](docs/ARCHITECTURE.md)
