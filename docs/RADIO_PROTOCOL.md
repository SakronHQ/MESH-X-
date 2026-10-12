# MESH-X LoRa Radio Protocol Specification

## 1. Overview
The MESH-X Radio Protocol governs over-the-air RF communications using Semtech SX1278 (RA-02) transceivers in the 433 MHz ISM band.

---

## 2. LoRa Physical Layer (PHY) Configuration

| Parameter | Default Value | Notes |
|---|---|---|
| **Carrier Frequency** | `433.175 MHz` | Default channel in the 433.05–434.79 MHz ISM band |
| **Bandwidth (BW)** | `125 kHz` | Standard LoRa bandwidth for optimum sensitivity and regulatory compliance |
| **Spreading Factor (SF)**| `SF9` | Balance between sensitivity (~ -128 dBm) and airtime (~200ms per msg) |
| **Coding Rate (CR)** | `4/7` | Enhanced forward error correction for noisy RF environments |
| **Preamble Length** | `8 symbols` | Standard preamble for reliable packet detection |
| **Sync Word** | `0x12` | Private network identifier (prevents cross-talk with LoRaWAN 0x34 or Meshtastic 0x2B) |
| **TX Power** | `+14 dBm (25 mW)` | Configurable up to +17 dBm (+20 dBm with PA_BOOST under legal limits) |
| **CRC** | Enabled | Hardware CRC on LoRa payload enabled |

---

## 3. Over-The-Air (OTA) Packet Frame

Every radio transmission uses a compact 16-byte fixed binary header to conserve limited channel airtime.

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  MAGIC (0x58) |  VER (0x01)   |  PACKET_TYPE  |     FLAGS     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|   TTL (8)     |   HOP_COUNT   |         RESERVED (16)         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                      PACKET_ID (32-bit uint)                  |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    SOURCE_NODE_ID (32-bit uint)               |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                  DESTINATION_NODE_ID (32-bit uint)            |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
| PAYLOAD_LEN(8)|      PAYLOAD / CIPHERTEXT (0..235 bytes)      |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                     CRC16 / AUTH CHECKSUM                     |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### 3.1 Field Specification
- `MAGIC`: `0x58` (ASCII 'X'). Rejects alien RF frames immediately.
- `VER`: Protocol version (`0x01`).
- `PACKET_TYPE`:
  - `0x01`: `PKT_TEXT_MSG` (Direct or broadcast chat message)
  - `0x02`: `PKT_ACK` (Hop-to-hop or end-to-end receipt)
  - `0x03`: `PKT_NODE_ANNOUNCE` (Periodic discovery broadcast)
  - `0x04`: `PKT_PING` / `0x05`: `PKT_PONG` (Link quality test)
  - `0x06`: `PKT_SOS` (Urgent emergency broadcast)
- `FLAGS`: Bitmask (`0x01` = Requires ACK, `0x02` = Encrypted, `0x04` = Relay allowed).
- `TTL`: Time-To-Live hop budget (Initialized to 3; decremented on each relay).
- `HOP_COUNT`: Incrementing hop counter for diagnostic tracing.
- `PACKET_ID`: 32-bit pseudo-random unique message identifier.
- `SOURCE_NODE_ID`: 32-bit identifier of originating ESP32 (derived from lower 4 bytes of MAC address).
- `DESTINATION_NODE_ID`: 32-bit identifier of recipient (`0xFFFFFFFF` denotes a global broadcast).
- `PAYLOAD_LEN`: Payload length in bytes (max 235 bytes).
- `CRC16`: CCITT checksum protecting header and payload fields.

---

## 4. Collision Avoidance & Channel Access
LoRa is a half-duplex shared medium. To prevent frame collisions:
1. **Channel Activity Detection (CAD)**: Before initiating TX, the ESP32 performs a CAD check via the SX1278 hardware.
2. **Backoff Mechanism**: If channel activity is detected, transmission backs off for a random interval:
   $$T_{\text{backoff}} = \text{random}(100\text{ ms}, 450\text{ ms}) \times (1 + \text{retry\_count})$$
3. **Duty Cycle & Airtime Management**: A strict 10% maximum duty cycle budget is enforced in firmware to avoid channel clogging and honor local RF rules.

---

## 5. Mesh Forwarding Rules (Phase 5+)
When an intermediate ESP32 receives an RF packet:
1. **Duplicate Filter**: Checks `PACKET_ID` against a 64-entry rolling LRU ring buffer. If already seen, the packet is silently dropped.
2. **Destination Check**: If `DESTINATION_NODE_ID == LOCAL_NODE_ID` or `DESTINATION_NODE_ID == 0xFFFFFFFF`, the packet is parsed and passed to the local BLE client.
3. **Relay Check**: If `DESTINATION_NODE_ID != LOCAL_NODE_ID` and `TTL > 1`:
   - Decrement `TTL` by 1.
   - Increment `HOP_COUNT` by 1.
   - Recompute CRC16.
   - Insert into outbound relay queue with a randomized jitter delay (50–200 ms) to avoid synchronization collisions across multiple relay nodes.
