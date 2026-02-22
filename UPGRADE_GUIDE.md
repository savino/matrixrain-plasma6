# Upgrade Guide — Horizontal Inline Renderer

## What Changed?

La modalità di rendering **"Horizontal Inline"** (mode 3) è stata completamente riscritta.

### Prima (HorizontalOverlayRenderer - legacy)

❌ **Problemi:**
- Messaggi MQTT mostrati con background nero visibile (box)
- Separazione visiva tra rain e messaggi MQTT
- Capacità massima: 5 messaggi
- Funzione `renderOverlay()` non chiamata dalla pipeline attuale

### Ora (HorizontalInlineRenderer - nuovo)

✅ **Miglioramenti:**
- Caratteri MQTT **iniettati nella griglia** del rain
- Zero background — i messaggi sembrano parte della pioggia
- Capacità massima: 15 messaggi
- Rendering two-pass: `renderColumnContent` + `renderInlineChars`
- Fade naturale dopo scadenza (3s default)

---

## Come Aggiornare

### 1️⃣ Scarica le modifiche

```bash
cd ~/path/to/matrixrain-plasma6
git pull origin main
```

### 2️⃣ Reinstalla il wallpaper

```bash
kpackagetool6 --type=Plasma/Wallpaper --upgrade package/
```

### 3️⃣ Riavvia Plasma Shell

**Metodo veloce:**
```bash
plasmashell --replace &
```

**Metodo completo (se il primo non funziona):**
```bash
killall plasmashell
kquitapp6 plasmashell
plasmashell &
```

### 4️⃣ Verifica la configurazione

1. Tasto destro sul desktop → **Configure Desktop and Wallpaper**
2. Tab **MQTT & Network**
3. Sezione **Behavior & Rendering**
4. **Render Mode** → seleziona **"Horizontal Inline (Matrix Inject)"**
5. Clicca **Apply**

---

## Verifica che Funzioni

### Test rapido

1. Abilita **Debug Overlay** nelle impostazioni
2. Invia un messaggio MQTT di test:
   ```bash
   mosquitto_pub -h homeassistant.lan -t "test/topic" -m '{"test": "value"}'
   ```
3. Dovresti vedere:
   - Messaggio appare **senza box nero**
   - Caratteri sembrano parte della pioggia Matrix
   - Topic in brightness media (40%)
   - Payload in brightness alta (85%)

### Check dei log

```bash
journalctl -f | grep -i "horizontalinline\|matrixrain"
```

Output atteso:
```
[MQTTRain] 🎭 Render mode changed to: Horizontal Inline
[HorizontalInlineRenderer] initializeColumns: 120 cols  canvas=1920x1080px
[HorizontalInlineRenderer] placed 25x3 at (45,12)  active=1/15
```

⚠️ **Se vedi `[MQTTInlineRenderer]` invece di `[HorizontalInlineRenderer]`:**
- Stai ancora usando il vecchio codice
- Forza un restart completo di Plasma (metodo completo sopra)

---

## Troubleshooting

### Problema: Vedo ancora i box neri

**Causa:** Cache di Plasma non aggiornata.

**Soluzione:**
```bash
# 1. Rimuovi completamente il wallpaper
kpackagetool6 --type=Plasma/Wallpaper --remove com.obsidianreq.matrixrain

# 2. Reinstalla da zero
cd ~/path/to/matrixrain-plasma6
kpackagetool6 --type=Plasma/Wallpaper --install package/

# 3. Restart completo
killall plasmashell && plasmashell &
```

### Problema: Messaggi MQTT non compaiono

**Check 1 - MQTT connesso?**
```bash
journalctl -f | grep "MQTT Connected"
```

**Check 2 - Topic blacklist?**
Controlla nelle impostazioni se il topic non è nella blacklist.

**Check 3 - Render mode corretto?**
Verifica che sia selezionato **"Horizontal Inline (Matrix Inject)"** (index 3).

### Problema: Errori di compilazione QML

**Sintomo:**
```
Cannot assign to non-existent property "renderInlineChars"
```

**Causa:** File vecchi mescolati con nuovi.

**Soluzione:**
```bash
# Rimuovi completamente la directory locale e riclona
cd ~
rm -rf matrixrain-plasma6
git clone https://github.com/savino/matrixrain-plasma6.git
cd matrixrain-plasma6
kpackagetool6 --type=Plasma/Wallpaper --install package/
```

---

## Breaking Changes per Sviluppatori

### Funzione rimossa

```qml
// ❌ DEPRECATED (non più chiamata da MatrixCanvas)
function renderOverlay(ctx) { ... }
```

### Funzione da usare

```qml
// ✅ NUOVO (chiamata dopo il rain loop)
function renderInlineChars(ctx) { ... }
```

### Renderer rimosso

- **File:** `package/contents/ui/renderers/HorizontalOverlayRenderer.qml`
- **Motivo:** Implementazione errata, sostituita da `HorizontalInlineRenderer.qml`
- **Migrazione:** Se hai estensioni custom, usa `HorizontalInlineRenderer` come base

---

## Documentazione Completa

- **Specifiche renderer:** [`docs/mqtt-specs.md`](docs/mqtt-specs.md#6-modalit%C3%A0-di-rendering-mqtt-renderers)
- **Architettura:** [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- **Changelog:** [`CHANGELOG.md`](CHANGELOG.md)

---

## Supporto

Se dopo aver seguito questa guida hai ancora problemi:

1. Controlla i log: `journalctl -f | grep MQTTRain`
2. Verifica la versione: `git log --oneline -5`
3. Apri una issue su GitHub con:
   - Output del comando `kpackagetool6 --type=Plasma/Wallpaper --list`
   - Screenshot del problema
   - Log completo di `journalctl`
