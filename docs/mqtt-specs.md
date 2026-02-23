# Specifiche MQTT per MatrixRain (Home Assistant + Zigbee2MQTT)

Questo documento descrive in modo formale e leggibile sia da umani sia da un assistente AI la struttura dei topic e dei payload MQTT usati da MatrixRain quando si collega a Home Assistant/Zigbee2MQTT.

Obiettivo principale:

- permettere al codice (e ad un coding assistant AI) di interpretare correttamente i messaggi ricevuti su `homeassistant/#` e `zigbee2mqtt/#`, distinguendo meta‑configurazione (MQTT Discovery) da dati runtime (stati, eventi, log, API).

---

## 1. Convenzioni generali

- **Broker**: Mosquitto integrato in Home Assistant, accessibile via TCP e/o WebSocket.
- **Base topic Zigbee2MQTT**: per default `zigbee2mqtt`, configurabile in `configuration.yaml` di Zigbee2MQTT (`mqtt.base_topic`).
- **Discovery prefix Home Assistant**: per default `homeassistant`, configurabile nell'integrazione MQTT.
- **Formato payload**: salvo casi espliciti, tutti i payload sono JSON UTF‑8.

> Nota per l'AI: tutti i riferimenti a `homeassistant/#` vanno interpretati come messaggi **di discovery/configurazione**, non come valori runtime dei sensori.

---

## 2. Topic `homeassistant/#` – MQTT Discovery di Home Assistant

Home Assistant usa MQTT Discovery per creare entità automaticamente. Lo schema formale del topic di discovery è:

```text
<discovery_prefix>/<component>/[<node_id>/]<object_id>/config
```

Dove:

- `<discovery_prefix>`: per default `homeassistant`.
- `<component>`: tipo di entità, es. `sensor`, `binary_sensor`, `switch`, `light`, `cover`, `button`, `device_tracker`, ecc.
- `<node_id>`: opzionale, serve per organizzare i topic ma **non** entra direttamente nell'`entity_id`.
- `<object_id>`: identificatore dell'entità, ammessi caratteri `[A-Za-z0-9_-]`.

Esempi di topic validi:

```text
homeassistant/sensor/sala_temperatura/config
homeassistant/light/living_room/lampada_soffitto/config
homeassistant/binary_sensor/porta_ingresso/config
```

### 2.1 Struttura generica del payload di discovery

Il payload della discovery è un oggetto JSON. Esistono vari campi specifici per ogni `component`, ma a livello generico si possono definire i seguenti campi comuni (tutti opzionali salvo diversamente indicato):

```jsonc
{
  "name": "<string>",                // Nome leggibile dell'entità
  "uniq_id": "<string>",            // Unique ID globale (es. per evitare duplicati)
  "state_topic": "<string>",        // Topic dove il device pubblica lo stato runtime
  "command_topic": "<string>",      // Topic su cui inviare comandi al device
  "availability_topic": "<string>", // Topic per lo stato online/offline del device
  "device": {                        // Metadati del device fisico
    "identifiers": ["<string>", ...],
    "manufacturer": "<string>",
    "model": "<string>",
    "name": "<string>"
  },
  "device_class": "<string>",        // Classe del sensore (es. temperature, power, motion...)
  "unit_of_measurement": "<string>", // Unità di misura (es. "°C", "%", "W")
  "icon": "<string>",               // Icona opzionale (mdi:...)
  "state_class": "<string>",        // Es. measurement, total_increasing
  "json_attributes_topic": "<string>", // Topic con attributi addizionali JSON
  "payload_on": "<any>",
  "payload_off": "<any>",
  "value_template": "<string>"       // Template per parsare il valore dal payload
}
```

> Regola per l'AI: quando incontri un topic `homeassistant/.../config`, **non aspettarti valori fisici (es. temperatura)**, ma solo metadati che dicono *dove* trovarli (vedi `state_topic`, `command_topic`, ecc.).

### 2.2 Abbreviazioni comunemente usate

Alcuni publisher (es. firmware custom, gateway) usano le forme abbreviate previste da Home Assistant. Mapping tipico:

- `stat_t` → `state_topic`
- `cmd_t` → `command_topic`
- `avty_t` → `availability_topic`
- `dev` → `device`
- `dev_cla` → `device_class`
- `unit_of_meas` → `unit_of_measurement`

> Regola per l'AI: normalizza sempre le abbreviazioni alle forme lunghe interne al progetto, così da avere uno schema unificato in memoria.

### 2.3 Relazione fra discovery e dati runtime

- I payload sotto `homeassistant/#` **non** contengono i valori runtime dei sensori.
- I valori runtime arrivano invece sui topic indicati dai campi `state_topic`, `command_topic`, `availability_topic`, `json_attributes_topic`, ecc.
- MatrixRain, se usa questi metadati, deve quindi:
  - parsare il JSON di discovery;
  - registrare internamente una mappa `entity → {state_topic, command_topic, ...}`;
  - sottoscriversi ai topic di stato effettivi (es. `zigbee2mqtt/TemperaturaSala`).

---

## 3. Topic `zigbee2mqtt/#` – dispositivi

Zigbee2MQTT pubblica i dati dei dispositivi su topic organizzati sotto un **base topic** (di default `zigbee2mqtt`).

### 3.1 Pattern generali di topic dispositivo

Assumendo `base_topic = zigbee2mqtt` e `FRIENDLY_NAME` come nome amichevole del device:

- Stato completo del device (lettura):

  ```text
  zigbee2mqtt/<FRIENDLY_NAME>
  ```

- Comandi al device (scrittura):

  ```text
  zigbee2mqtt/<FRIENDLY_NAME>/set
  zigbee2mqtt/<FRIENDLY_NAME>/get
  ```

- Availability del device:

  ```text
  zigbee2mqtt/<FRIENDLY_NAME>/availability
  ```

### 3.2 Modalità di output (`mqtt.output`)

Zigbee2MQTT può pubblicare i dati in tre modalità principali (impostazione `mqtt.output`):

1. **`json`** (default moderno)
   - Tutti gli attributi in un unico payload JSON su `zigbee2mqtt/<FRIENDLY_NAME>`.
   - Esempio:

     ```json
     {
       "state": "ON",
       "brightness": 200,
       "color_temp": 370,
       "linkquality": 76,
       "battery": 94
     }
     ```

   - Regola per l'AI: interpreta il payload come un oggetto key→value; i campi presenti dipendono dallo specifico device.

2. **`attribute`**
   - Un messaggio per ogni attributo, con topic distinto:

     ```text
     zigbee2mqtt/Console/state        payload: "OFF"
     zigbee2mqtt/Console/power        payload: "10.4"
     zigbee2mqtt/Console/linkquality  payload: "76"
     ```

   - Regola per l'AI: qui lo **schema sta nel topic**:
     - ultimo segmento del topic = nome attributo;
     - payload = valore scalare dell'attributo (stringa/numero/bool).

3. **`attribute_and_json`**
   - Un messaggio JSON completo come in `json`, **più** i singoli topic per attributo come in `attribute`.

> Suggerimento per MatrixRain: il codice dovrebbe essere in grado di rilevare automaticamente la modalità in uso osservando i topic ricevuti (es. se arrivano sia `zigbee2mqtt/X` con JSON sia `zigbee2mqtt/X/state` scalare, sei in `attribute_and_json`).

### 3.3 Schema logico del payload stato device (`json`)

Per uso interno/AI è utile modellare il payload JSON in modo generico:

```ts
interface DeviceStateJSON {
  state?: string;          // Es. "ON" | "OFF" | "OPEN" | "CLOSE" | "single" | "double" ...
  battery?: number;        // Percentuale batteria (0-100)
  voltage?: number;        // Tensione (es. V)
  power?: number;          // Potenza istantanea (es. W)
  energy?: number;         // Contatore energia (es. kWh)
  current?: number;        // Corrente (es. A)
  brightness?: number;     // 0-254 o 0-255 a seconda del device
  color_temp?: number;     // Mired (valore device-specific)
  linkquality?: number;    // Qualità link (LQI)
  occupancy?: boolean;     // Sensori di presenza
  contact?: boolean;       // Contatti porta/finestra
  temperature?: number;    // °C
  humidity?: number;       // %
  pressure?: number;       // hPa
  // ... altri attributi device-specific
  [key: string]: any;      // Campi aggiuntivi non mappati esplicitamente
}
```

> Regola per l'AI: considera `DeviceStateJSON` come schema **estensibile**; non fallire se ricevi campi non documentati, ma memorizzali comunque.

### 3.4 Availability e health dei device

Topic tipico di availability:

```text
zigbee2mqtt/<FRIENDLY_NAME>/availability
```

Il payload può essere:

- stringa: `"online"` / `"offline"` (modalità *legacy* o alcune configurazioni);
- JSON con campo `state`, ad esempio:

  ```json
  { "state": "online" }
  ```

Regole suggerite per MatrixRain / AI:

- se il payload è una stringa, normalizza a `{ "state": <string> }` internamente;
- se il payload è JSON, cerca il campo `state` come informazione primaria di availability.

---

## 4. Topic `zigbee2mqtt/bridge/*` – stato globale, log e API

Zigbee2MQTT espone un "bridge" MQTT con vari topic speciali.

### 4.1 Stato del bridge

```text
zigbee2mqtt/bridge/state
```

- Payload tipico (retained):

  ```json
  { "state": "online" }
  ```

  oppure

  ```json
  { "state": "offline" }
  ```

- Usato per capire se Zigbee2MQTT è attivo.

Schema logico:

```ts
interface BridgeState {
  state: "online" | "offline" | string; // consentire valori futuri/custom
}
```

### 4.2 Logging del bridge

```text
zigbee2mqtt/bridge/logging
```

- Contiene tutti i messaggi di log (salvo eventuale livello `debug` a seconda della configurazione).
- Payload tipico:

  ```json
  {
    "level": "info",          // info | warn | error | debug
    "message": "...",         // messaggio leggibile
    "namespace": "zigbee2mqtt" // o un namespace più specifico
  }
  ```

Schema logico:

```ts
interface BridgeLog {
  level: "info" | "warn" | "error" | "debug" | string;
  message: string;
  namespace?: string;
  [key: string]: any;
}
```

> Suggerimento: MatrixRain può usare questo topic per una "console di debug" in overlay sul wallpaper.

### 4.3 Eventi del bridge

```text
zigbee2mqtt/bridge/event
```

- Usato per eventi strutturati (es. `device_announce`, `device_leave`, ecc.).
- Payload generico:

  ```json
  {
    "type": "device_announce", // o altri tipi di evento
    "data": {                   // oggetto specifico per tipo
      "friendly_name": "LampadaSala",
      "ieee_address": "0x00124b0012345678"
      // ... altri campi
    }
  }
  ```

Schema logico:

```ts
interface BridgeEvent {
  type: string;      // device_announce, device_leave, etc.
  data: any;         // struttura variabile in base al tipo
}
```

> Regola per l'AI: non assumere uno schema rigido per `data`; fai pattern‑matching leggero (es. se c'è `friendly_name`, probabilmente è un evento di device).

### 4.4 API request/response via MQTT

Zigbee2MQTT espone una vera e propria API su MQTT, tramite coppie di topic `request`/`response`:

- Richieste:

  ```text
  zigbee2mqtt/bridge/request/<ENDPOINT>
  ```

- Risposte:

  ```text
  zigbee2mqtt/bridge/response/<ENDPOINT>
  ```

#### 4.4.1 Schema generico della richiesta

```ts
interface BridgeRequest {
  // Parametri specifici per endpoint (es. { "time": 254 } per permit_join)
  [key: string]: any;
}
```

Esempio:

- Topic: `zigbee2mqtt/bridge/request/permit_join`
- Payload:

  ```json
  { "time": 254 }
  ```

#### 4.4.2 Schema generico della risposta

```ts
interface BridgeResponse<T = any> {
  status: "ok" | "error" | string; // stato dell'operazione
  data: T;                           // dati specifici per l'endpoint
  error?: string;                    // messaggio di errore se status == "error"
  transaction?: number | string;     // opzionale, usato per correlare richiesta/risposta
  [key: string]: any;
}
```

Esempi:

- Risposta OK:

  ```json
  {
    "status": "ok",
    "data": { "time": 254 }
  }
  ```

- Risposta con errore:

  ```json
  {
    "status": "error",
    "error": "Invalid payload",
    "data": {}
  }
  ```

> Regola per l'AI: quando parsando un topic che inizia con `zigbee2mqtt/bridge/response/`, usa sempre lo schema `BridgeResponse`; non trattare questi messaggi come telemetria sensore.

---

## 5. Strategia di parsing per MatrixRain

Questa sezione definisce come il codice (e l'AI) dovrebbero ragionare quando ricevono un messaggio MQTT.

### 5.1 Classificazione dei topic

Dato un topic `T`:

1. Se `T` inizia con `homeassistant/` ed è del tipo `.../config`:
   - interpreta il payload come `HADiscoveryConfig`;
   - aggiorna la mappa di discovery interna.

2. Se `T` inizia con `zigbee2mqtt/bridge/state`:
   - interpreta il payload come `BridgeState`.

3. Se `T` inizia con `zigbee2mqtt/bridge/logging`:
   - interpreta il payload come `BridgeLog`.

4. Se `T` inizia con `zigbee2mqtt/bridge/event`:
   - interpreta il payload come `BridgeEvent`.

5. Se `T` inizia con `zigbee2mqtt/bridge/response/`:
   - interpreta il payload come `BridgeResponse`.

6. Se `T` corrisponde al pattern `zigbee2mqtt/<FRIENDLY_NAME>/availability`:
   - interpreta il payload come availability device, normalizzandolo a `{ state: string }`.

7. Se `T` corrisponde a `zigbee2mqtt/<FRIENDLY_NAME>` (senza ulteriori segmenti):
   - in modalità `json` o `attribute_and_json`, interpreta il payload come `DeviceStateJSON`.

8. Se `T` corrisponde al pattern `zigbee2mqtt/<FRIENDLY_NAME>/<ATTRIBUTE>` e `<ATTRIBUTE>` **non** è uno dei segmenti speciali (`set`, `get`, `availability`, `bridge`, `state`, `logging`, `event`, `request`, `response`):
   - in modalità `attribute` o `attribute_and_json`, interpreta il payload come valore scalare dell'attributo `<ATTRIBUTE>`.

### 5.2 Linee guida per l'AI durante il coding

- Quando si genera codice QML/JS per MatrixRain:
  - Usa sempre funzioni di utility per:
    - classificare il topic (`classifyTopic(topic: string)`);
    - fare il parse sicuro del payload (`safeParseJson(payload: string)` con fallback a stringa semplice);
    - normalizzare availability e log.
  - Non assumere mai che il payload sia sempre JSON: gestisci anche casi stringa pura (availability, alcuni log custom, ecc.).

- Quando devi suggerire mapping o visualizzazioni:
  - per `DeviceStateJSON`, suggerisci di esporre le chiavi come overlay dinamici (es. temperatura, potenza, battery, linkquality);
  - per `BridgeLog`, suggerisci output tipo console di debug;
  - per `BridgeState`, suggerisci uno stato globale (es. "Z2M online/offline").

- Quando devi scrivere test/dummy data:
  - genera messaggi che rispettano questi schemi di topic e payload;
  - evita di inventare campi non realistici se non necessari.

---

## 6. Modalità di rendering MQTT (Renderers)

MatrixRain espone diverse modalità di rendering che determinano come i messaggi MQTT vengono visualizzati sullo sfondo del wallpaper. Ogni modalità è implementata in un componente QML dedicato (`renderers/`).

### 6.1 Indice delle modalità

| # | Nome display | Componente | Descrizione breve |
|---|---|---|---|
| 0 | Mixed | `MixedModeRenderer.qml` | Rain verticale + messaggi MQTT in colonne dedicate |
| 1 | MQTT Only | `MqttOnlyRenderer.qml` | Solo messaggi MQTT verticali, nessuna pioggia casuale |
| 2 | MQTT Driven | `MqttDrivenRenderer.qml` | Colonne attive su arrivo messaggi, effetto burst |
| 3 | Horizontal Inject | `HorizontalInjectRenderer.qml` | Celle MQTT orizzontali a TTL 3s, ridisegnate ogni frame e trattate come ostacoli dal rain |

Nota: `ClassicRenderer.qml` viene usato come fallback automatico quando `mqttEnable=false` (non è una modalità selezionabile da `mqttRenderMode`).

### 6.2 Modalità 0 – Matrix Only (`ClassicRenderer`)

**Comportamento:**
- Rendering di pioggia Matrix verticale classica.
- Nessun messaggio MQTT visibile.
- Drop cadono continuamente con velocità configurabile.
- Colori palette applicati per colonna (se `colorMode > 0`).

**Interfaccia:**
- `assignMessage(topic, payload)` → no-op (ignorato).
- `renderColumnContent(ctx, col, x, y, drops)` → disegna char Katakana random.
- `onColumnWrap(col)` → reset drop head a y=0.

**Uso:**
Per sfondi puramente estetici senza sovrapposizione dati.

---

### 6.3 Modalità 1 – MQTT Only (`MqttOnlyRenderer`)

**Comportamento:**
- Nessuna pioggia Matrix.
- Ogni colonna mostra un singolo messaggio MQTT che scorre verticalmente.
- Il testo viene troncato/wrappato per adattarsi alla larghezza della colonna.
- Colori per colonna dal `colorMode` attivo.

**Interfaccia:**
- `assignMessage(topic, payload)`:
  - Assegna il messaggio alla colonna con meno caratteri attivi (load balancing).
  - Costruisce stringa `"topic: payload"`, tronca/wrapup se troppo lungo.
- `renderColumnContent(ctx, col, x, y, drops)`:
  - Disegna il carattere corrente del messaggio assegnato alla colonna.
  - Se nessun messaggio: disegna spazio vuoto (nessun Katakana).
- `onColumnWrap(col)` → libera la colonna per nuovi messaggi.

**Parametri:**
- `messageSpeed` (ms/frame, default 50) – velocità scroll verticale.

**Uso:**
Console-like, per debug o monitoring puro.

---

### 6.4 Modalità 2 – Mixed Mode (`MixedModeRenderer`)

**Comportamento:**
- Colonne alternate mostrano pioggia Matrix **o** messaggi MQTT.
- La distribuzione è configurabile tramite `ratio` (es. 70% rain, 30% MQTT).
- Colonne rain: drop verticali normali.
- Colonne MQTT: scroll verticale di topic+payload.

**Interfaccia:**
- `assignMessage(topic, payload)`:
  - Assegna alle colonne marcate come "MQTT" (round-robin o load balancing).
  - Costruisce testo come in `MqttOnlyRenderer`.
- `renderColumnContent(ctx, col, x, y, drops)`:
  - Se colonna rain → Katakana random.
  - Se colonna MQTT → char del messaggio attivo.
- `initializeColumns(numCols)`:
  - Marca colonne come `"rain"` o `"mqtt"` in base al `ratio`.

**Parametri:**
- `ratio` (0.0–1.0, default 0.7) – frazione di colonne dedicate al rain.
- `messageSpeed` (ms/frame, default 50).

**Uso:**
Bilanciamento visuale: estetica Matrix + visibilità dati MQTT.

---

### 6.5 Modalità 2 – MQTT Driven (`MqttDrivenRenderer`)

**Comportamento:**
- I messaggi MQTT **non** sono visualizzati direttamente.
- Invece, influenzano i parametri del rain (velocità, colore, jitter) per colonna.
- Mapping esempio:
  - `temperature` → velocità drop.
  - `brightness` → intensità colore.
  - `state` → cambio palette.

**Interfaccia:**
- `assignMessage(topic, payload)`:
  - Parsa payload per estrarre chiavi significative.
  - Assegna metriche a colonne specifiche (es. round-robin).
  - Modifica parametri interni (`dropSpeed[col]`, `colorIntensity[col]`).
- `renderColumnContent(ctx, col, x, y, drops)`:
  - Disegna Katakana con parametri modificati per quella colonna.
- `onColumnWrap(col)` → resetta parametri a default.

**Uso:**
Data-driven art: l'aspetto visivo riflette lo stato del sistema senza text overlay.

---

### 6.6 Selezione della modalità

La modalità attiva è controllata da:
- **`main.qml`** → `property int mqttRenderMode` (0–3).
- **Configurazione UI** → `config.qml` → `mqttRenderModeCombo`.

Quando l'utente cambia modalità:
1. `MatrixCanvas.qml` rileva il cambio di `renderMode`.
2. Chiama `initializeColumns(numCols)` sul nuovo renderer.
3. Reset drops e timer.

### 6.9 Best practices per nuovi renderer

Se si implementa una nuova modalità (es. mode 6), seguire:

1. **Interfaccia obbligatoria**:
   ```qml
   function assignMessage(topic, payload)   // gestione arrivo MQTT
   function renderColumnContent(ctx, col, x, y, drops)  // per-column rendering
   function onColumnWrap(col)               // reset stato colonna
   function initializeColumns(numCols)      // setup iniziale/resize
   ```

2. **Interfaccia opzionale**:
   ```qml
   function renderInlineChars(ctx)         // pass 2 rendering (post-rain)
   function renderOverlay(ctx)             // overlay widgets (deprecated)
   ```

3. **Binding property obbligatorie**:
   - `fontSize`, `baseColor`, `jitter`, `glitchChance`, `palettes`, `paletteIndex`, `colorMode`.
   - `canvasWidth`, `canvasHeight`.
   - `columns`, `columnAssignments` (compatibility stub).

4. **Timer e performance**:
   - Operazioni pesanti (es. JSON parse, network fetch) → fuori da `renderColumnContent`.
   - Timer interni → `interval >= 1000 ms` preferibile.
   - Evitare `Object.keys()` o flat map di `canvasWidth × canvasHeight` elementi.

5. **Coordinate grid consistency**:
   ```
   gridCol = Math.floor(pixelX / fontSize)
   gridRow = Math.floor(pixelY / fontSize)
   pixelX  = gridCol * fontSize
   pixelY  = (gridRow + 1) * fontSize   // baseline alfabetico
   ```

---

## 7. Estensioni future

Questo documento può essere esteso con:

- elenchi specifici di campi `DeviceStateJSON` per i device effettivamente presenti nell'impianto (es. `TRADFRI bulb`, `Sonoff plug`, ecc.);
- esempi reali di payload catturati dal broker, annotati con spiegazioni;
- mapping diretti fra `HADiscoveryConfig` e le entità usate dal wallpaper (es. quali sensori influenzano effetti grafici specifici).

Per ora, le regole sopra forniscono una base abbastanza stabile perché un assistente AI possa ragionare sulla struttura dei messaggi MQTT usati da MatrixRain e generare codice coerente.