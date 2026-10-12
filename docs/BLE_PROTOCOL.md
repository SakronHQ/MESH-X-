# MESH-X Bluetooth Low Energy (BLE) GATT Protocol

## 1. Overview
The MESH-X BLE protocol defines the local communication interface between the mobile Flutter application and the ESP32 hardware node.

All UUIDs are 128-bit custom identifiers derived from the `MESH-X` base UUID.

---

## 2. GATT Service & Characteristic UUIDs

### Base UUID Format
`4D455348-5800-xxxx-8000-00805F9B34FB` (ASCII `MESH-X`)

| Component | UUID | Properties | Description |
|---|---|---|---|
| **MESH-X Primary Service** | `4D455348-5800-0001-8000-00805F9B34FB` | — | Primary advertising and communication service |
| **Device Info Characteristic** | `4D455348-5800-0002-8000-00805F9B34FB` | `Read` | Node identity, hardware model, firmware & protocol version |
| **Command In Characteristic** | `4D455348-5800-0003-8000-00805F9B34FB` | `WriteWithoutResponse` / `Write` | Inbound binary frames from Mobile App to ESP32 |
| **Event Out Characteristic** | `4D455348-5800-0004-8000-00805F9B34FB` | `Notify` | Outbound binary notifications from ESP32 to Mobile App |
| **Telemetry Characteristic** | `4D455348-5800-0005-8000-00805F9B34FB` | `Read`, `Notify` | Radio metrics (RSSI, SNR), queue depth, battery telemetry |

---

## 3. BLE Framing Protocol

Due to BLE MTU limitations (default BLE ATT MTU can be as low as 23 bytes, yielding 20 bytes effective payload), all data over Command In and Event Out characteristics is framed with a binary header.

### 3.1 Binary Frame Structure
```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|       MAGIC (0xAA, 0x58)      |    VER (0x01) |   FRAME_TYPE  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|          SEQ_NUM (16)         |       TOTAL_PAYLOAD_LEN (16)  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|         FRAG_INDEX (8)        |       FRAG_COUNT (8)          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    VARIABLE PAYLOAD (0..N bytes)              |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                        CRC16 (16-bit CCITT)                   |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 3.2 Field Descriptions
- `MAGIC`: `0xAA58` (`AA` sync mark, `X` ASCII 0x58). Discards noise/garbage.
- `VER`: Protocol version (`0x01`).
- `FRAME_TYPE`: Identifies command or notification payload type.
- `SEQ_NUM`: Monotonically increasing frame identifier for correlation and duplicate detection.
- `TOTAL_PAYLOAD_LEN`: Total length of the message payload across all fragments.
- `FRAG_INDEX`: 0-indexed fragment number (for multi-packet BLE transfers).
- `FRAG_COUNT`: Total fragments comprising this complete message.
- `PAYLOAD`: Data bytes (bounded by negotiated ATT MTU - 12 bytes).
- `CRC16`: CCITT polynomial (`0x1021`) computed over the entire frame header and payload.

---

## 4. Command & Event Types

### 4.1 Commands (App → ESP32)
| Code | Name | Description |
|---|---|---|
| `0x10` | `CMD_SUBMIT_MESSAGE` | Submit a text message for radio transmission |
| `0x11` | `CMD_PING` | Ping ESP32 to verify link liveness |
| `0x12` | `CMD_SET_RADIO_CONFIG` | Adjust frequency, spreading factor, or TX power |
| `0x13` | `CMD_GET_TELEMETRY` | Request immediate radio and hardware metrics |
| `0x14` | `CMD_SUBMIT_SOS` | Trigger high-priority broadcast SOS packet |

### 4.2 Events (ESP32 → App)
| Code | Name | Description |
|---|---|---|
| `0x80` | `EVT_RX_MESSAGE` | Inbound LoRa message received over the air |
| `0x81` | `EVT_TX_STATUS` | Status update for submitted packet (QUEUED, TRANSMITTED, FAILED) |
| `0x82` | `EVT_DELIVERY_ACK` | End-to-end LoRa ACK received from destination node |
| `0x83` | `EVT_PONG` | Response to `CMD_PING` |
| `0x84` | `EVT_NODE_DISCOVERED` | Announcement heard from a new mesh neighbor |
| `0x85` | `EVT_ERROR` | Command validation error or hardware fault |

---

## 5. MTU Negotiation & Fragmentation Policy
1. Upon BLE connection, the Flutter app requests an MTU update to **256 bytes**.
2. If the OS accepts (Android commonly negotiates 247-512 bytes), single-frame transfers are used for all messages up to 240 bytes.
3. If the host platform (e.g. certain iOS devices or legacy chipsets) limits MTU to 23 bytes, the protocol automatically shards payloads into fragments (`FRAG_INDEX` / `FRAG_COUNT`).
4. Reassembly is bounded by a 3.0-second timeout on the ESP32. Uncompleted frames are discarded to prevent memory leaks.
