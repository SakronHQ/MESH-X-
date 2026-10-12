# MESH-X System Architecture Specification

## 1. Executive Summary
MESH-X is an offline, peer-to-peer, and multi-hop mesh messaging system engineered to provide dependable off-grid text and SOS communications. The ecosystem pairs a mobile device running a Flutter client with an ESP32 microcontroller acting as a LoRa radio modem and autonomous mesh router.

---

## 2. System Overview & Data Flow

```
+-----------------------------------------------------------------------------------+
|                              MOBILE APPLICATION LAYER                             |
|                                                                                   |
|  +--------------------+     +---------------------+     +----------------------+  |
|  |   UI / UX Views    | --> | Riverpod State Mgmt | --> | SQLite Local Storage |  |
|  +--------------------+     +----------+----------+     +----------------------+  |
|                                        |                                          |
|                             +----------v----------+                               |
|                             | BLE Client Service  |                               |
+-----------------------------+----------+----------+-------------------------------+
                                         |
                                         | Bluetooth Low Energy (GATT Framing)
                                         v
+-----------------------------------------------------------------------------------+
|                              ESP32 FIRMWARE LAYER                                 |
|                                                                                   |
|  +-------------------------------------+     +---------------------------------+  |
|  |       BLE GATT Server Task          | <-> |       Queue Manager Task        |  |
|  | (Command In / Event Out / Telemetry)|     | (Deduplication, Buffering, TTL) |  |
|  +-------------------------------------+     +----------------+----------------+  |
|                                                               |                   |
|                                                      +--------v--------+          |
|                                                      | Radio MAC Task  |          |
|                                                      | (RadioLib/SPI)  |          |
+------------------------------------------------------+--------+--------+----------+
                                                                |
                                                                | Hardware SPI (VSPI)
                                                                v
+-----------------------------------------------------------------------------------+
|                             PHYSICAL RADIO LAYER                                  |
|                                                                                   |
|                        +-------------------------------+                          |
|                        | Semtech SX1278 (RA-02 Module) |                          |
|                        | 433 MHz RF Carrier (LoRa PHY) |                          |
+------------------------+-------------------------------+--------------------------+
```

---

## 3. Component Boundaries & Responsibilities

### 3.1 Mobile Application (`mesh_x_app`)
- **Device Discovery & Management**: Scanning for MESH-X BLE advertising packets, RSSI filtering, connection negotiation, and background reconnect logic.
- **Local Persistence**: SQLite database storing complete conversation histories, messages, contacts, encryption keys, and pending outbound queues.
- **Presentation & UX**: High-contrast dark UI (Riverpod-managed), showing accurate transmission lifecycle states without blocking when hardware is offline.
- **Security Boundary**: Generation and secure storage of end-to-end cryptographic keys (Phase 6). The mobile app will encrypt payloads before handing them to the ESP32.

### 3.2 Hardware Node (`mesh_x_firmware`)
- **BLE GATT Server**: Exposes standard MESH-X GATT services, validates inbound binary command frames, and emits asynchronous notifications for LoRa events.
- **Autonomous Mesh Routing**: Evaluates incoming LoRa packets, drops duplicates via rolling sliding-window cache, decrements TTL, and forwards valid packets without requiring mobile CPU intervention.
- **Radio Scheduling & Airtime**: Manages transmit queues, implements random backoff and listen-before-talk (CAD) heuristics to mitigate collisions on the shared RF channel.
- **Diagnostics**: Monitors radio RSSI, SNR, packet drop rates, and battery levels (when hardware ADC is wired).

---

## 4. State Machines

### 4.1 Connection Lifecycle State Machine
```
[ Disconnected ] 
       | (Initiate Scan)
       v
  [ Scanning ] ----(Device Found)----> [ Connecting ]
       |                                     |
 (Timeout / Cancel)                          v
       |                              [ Handshaking ] (Verify Protocol & Node ID)
       v                                     |
[ Disconnected ] <----(Disconnect/Error)-----+----(Handshake OK)----> [ Connected ]
       ^                                                                   |
       |---------------(Link Loss with Reconnect Enabled)------------------v
                                                                     [ Reconnecting ]
```

### 4.2 Message Delivery Lifecycle State Machine
```
   [ DRAFT ]
       | (User presses send)
       v
   [ QUEUED ] (Stored in SQLite; submitted to BLE Command Characteristic)
       |
       | (ESP32 acknowledges radio packet transmission)
       v
 [ TRANSMITTED ] (Local radio broadcast completed; airtime consumed)
       |
       +-------------------------------+
       |                               |
 (Direct ACK received)         (Max retries exceeded / ACK timeout)
       |                               |
       v                               v
 [ DELIVERED ]                     [ FAILED ]
                                       |
                               (User triggers manual retry)
                                       |
                                       +-----> [ QUEUED ]
```

---

## 5. Non-Functional Requirements & Constraints

1. **Airtime Efficiency**: Standard message packets must remain under 250 bytes to comply with LoRa PHY constraints and minimize on-air duration.
2. **Offline-First Guarantees**: The mobile app must remain fully interactive even if Bluetooth is switched off or no hardware node is within range. Outbound messages remain `QUEUED` until a link is restored.
3. **Power Budget**: The ESP32 firmware must conserve power by utilizing FreeRTOS sleep/tickless mechanisms where viable without missing LoRa RX interrupts on GPIO 26 (DIO0).
