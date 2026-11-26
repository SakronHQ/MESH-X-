/**
 * =============================================================================
 * MESH-X MAIN NODE FIRMWARE (Phase 5: Multi-Hop Mesh Routing & Deduplication)
 * Target: ESP32 DevKit V1 + SX1278 RA-02 (433 MHz)
 * 
 * Functions:
 * 1. BLE GATT Server (Command In, Event Out, Telemetry, Device Info)
 * 2. SX1278 LoRa Radio Driver (RadioLib, 433.175 MHz, Non-blocking DIO0)
 * 3. Bidirectional Bridge: Phone A <-> BLE <-> ESP32 <-> LoRa <-> ESP32 <-> BLE <-> Phone B
 * 4. Multi-hop Mesh Router:
 *    - 64-entry LRU ring buffer for duplicate suppression
 *    - Neighbor node table (1-hop & multi-hop metrics: RSSI, SNR, Hop distance)
 *    - Autonomous packet relaying with TTL decrement and randomized CAD jitter
 *    - Periodic background node presence broadcast (OTA_PKT_NODE_ANNOUNCE)
 * 5. Over-the-air Auto ACK and Delivery Receipts
 * =============================================================================
 */

#include <Arduino.h>
#include <SPI.h>
#include <RadioLib.h>
#include "../src/mesh_x_config.h"
#include "../src/mesh_x_protocol.h"
#include "../src/mesh_x_ble.h"
#include "../src/mesh_router.h"

// RadioLib SX1278 Module
SX1278 radio = new Module(LORA_CS, LORA_DIO0, LORA_RST);
bool g_radioInitialized = false;

// BLE Server instance
MeshXBLE ble;

// Mesh Router instance
MeshRouter g_router;

// Node Identity & Globals
uint32_t g_localNodeId = 0;
volatile bool g_radioDio0Triggered = false;
uint32_t g_lastTelemetryTime = 0;
uint32_t g_lastAnnounceTime = 0;

// Thread-safe outbound TX & RadioConfig queues (Core 0 BLE -> Core 1 LoRa loop)
#define TX_QUEUE_SIZE 8
struct OutboundTxItem {
  uint8_t  data[256];
  size_t   len;
  uint32_t packetId;
  bool     notifyStatus;
};

portMUX_TYPE g_txMux = portMUX_INITIALIZER_UNLOCKED;
OutboundTxItem g_txQueue[TX_QUEUE_SIZE];
size_t g_txHead = 0;
size_t g_txTail = 0;
size_t g_txCount = 0;

bool enqueueOtaTx(const uint8_t* buf, size_t len, uint32_t packetId, bool notifyStatus) {
  if (len == 0 || len > 256) return false;
  bool enqueued = false;
  portENTER_CRITICAL(&g_txMux);
  if (g_txCount < TX_QUEUE_SIZE) {
    memcpy(g_txQueue[g_txTail].data, buf, len);
    g_txQueue[g_txTail].len = len;
    g_txQueue[g_txTail].packetId = packetId;
    g_txQueue[g_txTail].notifyStatus = notifyStatus;
    g_txTail = (g_txTail + 1) % TX_QUEUE_SIZE;
    g_txCount++;
    enqueued = true;
  }
  portEXIT_CRITICAL(&g_txMux);
  return enqueued;
}

bool dequeueOtaTx(OutboundTxItem* out) {
  bool hasItem = false;
  portENTER_CRITICAL(&g_txMux);
  if (g_txCount > 0) {
    *out = g_txQueue[g_txHead];
    g_txHead = (g_txHead + 1) % TX_QUEUE_SIZE;
    g_txCount--;
    hasItem = true;
  }
  portEXIT_CRITICAL(&g_txMux);
  return hasItem;
}

// Radio packet types (OTA)
#define OTA_PKT_TEXT_MSG       0x01
#define OTA_PKT_ACK            0x02
#define OTA_PKT_NODE_ANNOUNCE  0x03
#define OTA_PKT_SOS            0x04

#define OTA_FLAG_REQ_ACK       0x01
#define OTA_FLAG_ENCRYPTED     0x02
#define OTA_FLAG_BROADCAST     0x04
#define OTA_FLAG_SOS           0x08

#pragma pack(push, 1)
struct OtaPacketHeader {
  uint8_t  magic;        // 0x58 ('X')
  uint8_t  version;      // 0x01
  uint8_t  packetType;   // OTA_PKT_*
  uint8_t  flags;        // OTA_FLAG_*
  uint8_t  ttl;          // Hop budget (3)
  uint8_t  hopCount;     // Incremented on relay
  uint32_t packetId;     // Unique message identifier
  uint32_t srcNode;      // Originating node ID
  uint32_t destNode;     // Target node ID (0xFFFFFFFF = broadcast)
  uint8_t  payloadLen;   // Length of text payload
};
#pragma pack(pop)

#if defined(ESP8266) || defined(ESP32)
  ICACHE_RAM_ATTR
#endif
void onRadioDio0(void) {
  g_radioDio0Triggered = true;
}

// Transmit an over-the-air raw buffer (MUST only be called from Core 1 loop())
bool transmitOtaBuffer(const uint8_t* buffer, size_t totalLen) {
  if (!g_radioInitialized) return false;
  radio.standby();
  g_radioDio0Triggered = false;
  int16_t state = radio.startTransmit((uint8_t*)buffer, totalLen);
  bool success = false;
  if (state == RADIOLIB_ERR_NONE) {
    uint32_t startMs = millis();
    // 4500ms timeout safely covers worst-case SF12 long-payload Time-on-Air
    while (!g_radioDio0Triggered && (millis() - startMs < 4500)) {
      yield();
    }
    success = g_radioDio0Triggered;
    if (!success) {
      Serial.println(F("[RADIO TX WARN] TX timeout (DIO0 interrupt not received)."));
    }
  } else {
    Serial.printf("[RADIO TX ERR] startTransmit code: %d\n", state);
  }

  // Clear TX state cleanly in standby before re-arming non-blocking RX
  radio.standby();
  g_radioDio0Triggered = false;
  radio.startReceive();
  return success;
}

// Relay an over-the-air packet across the mesh
void relayPacket(const uint8_t* originalPacket, size_t packetLen) {
  if (packetLen < sizeof(OtaPacketHeader) + 2 || packetLen > 256) return;

  uint8_t relayBuf[256];
  memcpy(relayBuf, originalPacket, packetLen);
  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(relayBuf);

  if (hdr->ttl <= 1 || hdr->hopCount >= 5) {
    Serial.printf("[ROUTER] TTL/Hop limit reached for packet 0x%08X. Dropping.\n", (unsigned int)hdr->packetId);
    return;
  }

  // Decrement TTL and increment hop count
  hdr->ttl--;
  hdr->hopCount++;

  // Recompute CRC-16
  uint16_t crc = computeCrc16(relayBuf, packetLen - 2);
  relayBuf[packetLen - 2] = (uint8_t)(crc & 0xFF);
  relayBuf[packetLen - 1] = (uint8_t)((crc >> 8) & 0xFF);

  // Randomized collision-avoidance jitter (50ms - 200ms)
  delay(random(50, 200));

  Serial.printf("[ROUTER RELAY] Forwarding packet 0x%08X (Dest: 0x%08X, TTL: %d, Hops: %d)\n",
    (unsigned int)hdr->packetId, (unsigned int)hdr->destNode, hdr->ttl, hdr->hopCount);

  transmitOtaBuffer(relayBuf, packetLen);
}

// Send an OTA ACK frame back to sender
void sendOtaAck(uint32_t packetId, uint32_t targetNode) {
  uint8_t buf[sizeof(OtaPacketHeader) + 2];
  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(buf);
  hdr->magic = MESH_MAGIC_BYTE;
  hdr->version = MESH_PROTO_VERSION;
  hdr->packetType = OTA_PKT_ACK;
  hdr->flags = 0;
  hdr->ttl = 5;
  hdr->hopCount = 0;
  hdr->packetId = packetId;
  hdr->srcNode = g_localNodeId;
  hdr->destNode = targetNode;
  hdr->payloadLen = 0;

  uint16_t crc = computeCrc16(buf, sizeof(OtaPacketHeader));
  buf[sizeof(OtaPacketHeader)] = (uint8_t)(crc & 0xFF);
  buf[sizeof(OtaPacketHeader) + 1] = (uint8_t)((crc >> 8) & 0xFF);

  Serial.printf("[RADIO ACK TX] Replying ACK for Packet ID 0x%08X to Node 0x%08X\n", (unsigned int)packetId, (unsigned int)targetNode);
  transmitOtaBuffer(buf, sizeof(buf));
}

// Broadcast periodic node presence across the mesh
void sendNodeAnnounce() {
  uint8_t buf[sizeof(OtaPacketHeader) + 2];
  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(buf);
  hdr->magic = MESH_MAGIC_BYTE;
  hdr->version = MESH_PROTO_VERSION;
  hdr->packetType = OTA_PKT_NODE_ANNOUNCE;
  hdr->flags = 0;
  hdr->ttl = 2; // Propagate up to 2 hops
  hdr->hopCount = 0;
  hdr->packetId = (uint32_t)random(1, 0x7FFFFFFF);
  hdr->srcNode = g_localNodeId;
  hdr->destNode = 0xFFFFFFFF; // Broadcast
  hdr->payloadLen = 0;

  // Suppress our own announce packet
  g_router.isDuplicate(g_localNodeId, hdr->packetId);

  uint16_t crc = computeCrc16(buf, sizeof(OtaPacketHeader));
  buf[sizeof(OtaPacketHeader)] = (uint8_t)(crc & 0xFF);
  buf[sizeof(OtaPacketHeader) + 1] = (uint8_t)((crc >> 8) & 0xFF);

  Serial.printf("[MESH ANNOUNCE] Broadcasting node presence (Node 0x%08X)\n", (unsigned int)g_localNodeId);
  transmitOtaBuffer(buf, sizeof(buf));
}

// Callback invoked when mobile app submits message via BLE (runs on Core 0 BLE task - DO NOT block on LoRa!)
void onMobileMessageSubmitted(const uint8_t* payload, size_t len) {
  // Expected payload: [PACKET_ID: 4B][DEST_NODE: 4B][FLAGS: 1B][TEXT]
  if (len < 9) {
    Serial.println(F("[BRIDGE ERR] Submitted message payload too short."));
    return;
  }

  uint32_t packetId = 0;
  uint32_t destNode = 0;
  memcpy(&packetId, payload, 4);
  memcpy(&destNode, payload + 4, 4);
  uint8_t flags     = payload[8];
  if (destNode == 0xFFFFFFFF) {
    flags |= OTA_FLAG_BROADCAST;
  }
  const char* text  = reinterpret_cast<const char*>(payload + 9);
  size_t textLen    = len - 9;

  Serial.printf("[BRIDGE] Queued Msg from Mobile: PktID 0x%08X -> Dest 0x%08X (len %d)\n",
    (unsigned int)packetId, (unsigned int)destNode, (int)textLen);

  // Build OTA Frame
  size_t otaTotalLen = sizeof(OtaPacketHeader) + textLen + 2;
  uint8_t otaBuf[256];
  if (otaTotalLen > sizeof(otaBuf)) {
    Serial.println(F("[BRIDGE ERR] Message exceeds RF packet limit."));
    ble.sendTxStatusForPacket(0, TX_STATUS_FAILED, packetId);
    return;
  }

  // Suppress our own outbound packet from being relayed back to us
  g_router.isDuplicate(g_localNodeId, packetId);

  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(otaBuf);
  hdr->magic = MESH_MAGIC_BYTE;
  hdr->version = MESH_PROTO_VERSION;
  hdr->packetType = OTA_PKT_TEXT_MSG;
  hdr->flags = flags;
  hdr->ttl = 5;
  hdr->hopCount = 0;
  hdr->packetId = packetId;
  hdr->srcNode = g_localNodeId;
  hdr->destNode = destNode;
  hdr->payloadLen = (uint8_t)textLen;

  if (textLen > 0) {
    memcpy(otaBuf + sizeof(OtaPacketHeader), text, textLen);
  }

  uint16_t crc = computeCrc16(otaBuf, sizeof(OtaPacketHeader) + textLen);
  otaBuf[sizeof(OtaPacketHeader) + textLen] = (uint8_t)(crc & 0xFF);
  otaBuf[sizeof(OtaPacketHeader) + textLen + 1] = (uint8_t)((crc >> 8) & 0xFF);

  if (!enqueueOtaTx(otaBuf, otaTotalLen, packetId, true)) {
    Serial.println(F("[BRIDGE ERR] Outbound TX queue full."));
    ble.sendTxStatusForPacket(0, TX_STATUS_FAILED, packetId);
  }
}

// Callback invoked when mobile app submits an emergency SOS broadcast (runs on Core 0 BLE task)
void onMobileSosSubmitted(const uint8_t* payload, size_t len) {
  // Expected payload: [PACKET_ID: 4B][BODY_BYTES...]
  if (len < 4) {
    Serial.println(F("[SOS ERR] Submitted SOS payload too short."));
    return;
  }

  uint32_t packetId = 0;
  memcpy(&packetId, payload, 4);
  const uint8_t* sosBody = payload + 4;
  size_t sosBodyLen = len - 4;

  Serial.printf("[SOS BROADCAST] Queuing Emergency SOS! Packet ID 0x%08X (len %d)\n",
    (unsigned int)packetId, (int)sosBodyLen);

  size_t otaTotalLen = sizeof(OtaPacketHeader) + sosBodyLen + 2;
  uint8_t otaBuf[256];
  if (otaTotalLen > sizeof(otaBuf)) {
    Serial.println(F("[SOS ERR] SOS payload exceeds RF limit."));
    ble.sendTxStatusForPacket(0, TX_STATUS_FAILED, packetId);
    return;
  }

  g_router.isDuplicate(g_localNodeId, packetId);

  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(otaBuf);
  hdr->magic = MESH_MAGIC_BYTE;
  hdr->version = MESH_PROTO_VERSION;
  hdr->packetType = OTA_PKT_SOS;
  hdr->flags = OTA_FLAG_SOS;
  hdr->ttl = 5;
  hdr->hopCount = 0;
  hdr->packetId = packetId;
  hdr->srcNode = g_localNodeId;
  hdr->destNode = 0xFFFFFFFF; // Flood broadcast
  hdr->payloadLen = (uint8_t)sosBodyLen;

  if (sosBodyLen > 0) {
    memcpy(otaBuf + sizeof(OtaPacketHeader), sosBody, sosBodyLen);
  }

  uint16_t crc = computeCrc16(otaBuf, sizeof(OtaPacketHeader) + sosBodyLen);
  otaBuf[sizeof(OtaPacketHeader) + sosBodyLen] = (uint8_t)(crc & 0xFF);
  otaBuf[sizeof(OtaPacketHeader) + sosBodyLen + 1] = (uint8_t)((crc >> 8) & 0xFF);

  if (!enqueueOtaTx(otaBuf, otaTotalLen, packetId, true)) {
    Serial.println(F("[SOS ERR] Outbound TX queue full."));
    ble.sendTxStatusForPacket(0, TX_STATUS_FAILED, packetId);
  }
}

#pragma pack(push, 1)
struct RadioConfigPayload {
  uint32_t freqKhz;
  uint8_t  sf;
  uint16_t bwKhz;
  uint8_t  cr;
  int8_t   txPower;
};
#pragma pack(pop)

volatile bool g_hasPendingRadioCfg = false;
RadioConfigPayload g_pendingRadioCfg;

void applyPendingRadioConfig() {
  RadioConfigPayload cfg;
  bool hasCfg = false;
  portENTER_CRITICAL(&g_txMux);
  if (g_hasPendingRadioCfg) {
    cfg = g_pendingRadioCfg;
    g_hasPendingRadioCfg = false;
    hasCfg = true;
  }
  portEXIT_CRITICAL(&g_txMux);

  if (!hasCfg || !g_radioInitialized) return;

  float newFreq = (float)cfg.freqKhz / 1000.0f;
  float newBw = (float)cfg.bwKhz;
  uint8_t newSf = cfg.sf;
  uint8_t newCr = cfg.cr;
  int8_t newPower = cfg.txPower;

  Serial.printf("[RADIO CFG] Reconfiguring LoRa: Freq: %.3f MHz, SF%u, BW %.1fkHz, CR 4/%u, Power: %d dBm\n",
    newFreq, (unsigned int)newSf, newBw, (unsigned int)newCr, (int)newPower);

  radio.standby();
  int16_t state = radio.setFrequency(newFreq);
  if (state != RADIOLIB_ERR_NONE) Serial.printf("[RADIO CFG ERR] setFrequency failed: %d\n", state);
  state = radio.setSpreadingFactor(newSf);
  if (state != RADIOLIB_ERR_NONE) Serial.printf("[RADIO CFG ERR] setSpreadingFactor failed: %d\n", state);
  state = radio.setBandwidth(newBw);
  if (state != RADIOLIB_ERR_NONE) Serial.printf("[RADIO CFG ERR] setBandwidth failed: %d\n", state);
  state = radio.setCodingRate(newCr);
  if (state != RADIOLIB_ERR_NONE) Serial.printf("[RADIO CFG ERR] setCodingRate failed: %d\n", state);
  state = radio.setOutputPower(newPower);
  if (state != RADIOLIB_ERR_NONE) Serial.printf("[RADIO CFG ERR] setOutputPower failed: %d\n", state);
  g_radioDio0Triggered = false;
  radio.startReceive();
  Serial.println(F("[RADIO CFG] SX1278 parameters updated and RX resumed."));
}

// Callback invoked when mobile app submits dynamic radio configuration (runs on Core 0 BLE task)
void onMobileRadioConfigSubmitted(const uint8_t* payload, size_t len) {
  if (len < sizeof(RadioConfigPayload)) {
    Serial.println(F("[RADIO CFG ERR] Payload too short."));
    return;
  }
  portENTER_CRITICAL(&g_txMux);
  memcpy(&g_pendingRadioCfg, payload, sizeof(RadioConfigPayload));
  g_hasPendingRadioCfg = true;
  portEXIT_CRITICAL(&g_txMux);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // 1. Unique Node ID from factory MAC
  uint64_t mac = ESP.getEfuseMac();
  g_localNodeId = (uint32_t)(mac & 0xFFFFFFFF);

  Serial.println(F("\n========================================================"));
  Serial.println(F("       MESH-X NODE FIRMWARE (Phase 5 Mesh Router)       "));
  Serial.println(F("========================================================"));
  Serial.printf("Local Node ID    : 0x%08X (MESH-X-%06X)\n", (unsigned int)g_localNodeId, (unsigned int)(g_localNodeId & 0xFFFFFF));
  Serial.printf("LoRa Frequency   : %.3f MHz (SF%d, BW %.1fkHz)\n", LORA_FREQ, LORA_SF, LORA_BW);

  // 2. Initialize VSPI and SX1278
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_CS);
  int16_t radioState = radio.begin(
    LORA_FREQ, LORA_BW, LORA_SF, LORA_CR,
    LORA_SYNC_WORD, LORA_TX_POWER, LORA_PREAMBLE_LEN, LORA_GAIN
  );

  if (radioState == RADIOLIB_ERR_NONE) {
    g_radioInitialized = true;
    Serial.println(F("[INIT] SX1278 LoRa transceiver initialized successfully."));
  } else {
    g_radioInitialized = false;
    Serial.printf("[INIT WARN] SX1278 init returned code %d. Verify SPI wiring & 3.3V.\n", radioState);
  }

  radio.setDio0Action(onRadioDio0, RISING);
  radio.startReceive();

  // 3. Initialize BLE GATT Server
  ble.onMessageSubmitted(onMobileMessageSubmitted);
  ble.onSosSubmitted(onMobileSosSubmitted);
  ble.onRadioConfigSubmitted(onMobileRadioConfigSubmitted);
  ble.begin(g_localNodeId, "1.4.0");
  Serial.println(F("[INIT] BLE, LoRa Radio and Mesh Router initialized (Phase 7 SOS Active).\n"));
}

void loop() {
  ble.loop();
  applyPendingRadioConfig();

  // Handle Radio Inbound Packets
  if (g_radioDio0Triggered) {
    g_radioDio0Triggered = false;

    uint8_t rxBuffer[256];
    size_t rxLen = radio.getPacketLength();

    if (rxLen >= sizeof(OtaPacketHeader) + 2 && rxLen <= sizeof(rxBuffer)) {
      int16_t state = radio.readData(rxBuffer, rxLen);
      if (state == RADIOLIB_ERR_NONE) {
        uint16_t expectedCrc = computeCrc16(rxBuffer, rxLen - 2);
        uint16_t receivedCrc = (uint16_t)rxBuffer[rxLen - 2] | ((uint16_t)rxBuffer[rxLen - 1] << 8);

        if (expectedCrc == receivedCrc) {
          const OtaPacketHeader* hdr = reinterpret_cast<const OtaPacketHeader*>(rxBuffer);
          size_t maxPayload = rxLen - sizeof(OtaPacketHeader) - 2;

          if (hdr->magic == MESH_MAGIC_BYTE && hdr->payloadLen <= maxPayload) {
            // 1. Ignore our own echoed packets & check (srcNode, packetId) duplicate cache
            if (hdr->srcNode == g_localNodeId ||
                g_router.isDuplicate(hdr->srcNode, hdr->packetId)) {
              Serial.printf("[ROUTER] Dropping duplicate/own packet 0x%08X from 0x%08X\n",
                (unsigned int)hdr->packetId, (unsigned int)hdr->srcNode);
            } else {
              float rssi = radio.getRSSI();
              float snr  = radio.getSNR();

              // 2. Record neighbor node & notify mobile app via BLE
              uint8_t calculatedHops = hdr->hopCount + 1;
              g_router.recordNeighbor(hdr->srcNode, calculatedHops, rssi, snr);
              ble.sendNodeDiscovered(hdr->srcNode, calculatedHops, rssi, snr);

              // 3. Address matching & Multi-hop forwarding
              bool isForMe = (hdr->destNode == g_localNodeId);
              bool isBroadcast = (hdr->destNode == 0xFFFFFFFF);

              if (isForMe) {
                if (hdr->packetType == OTA_PKT_TEXT_MSG) {
                  Serial.printf("[LORA RX] Direct Msg from 0x%08X (Hops: %u, Len: %u, RSSI: %.1f, SNR: %.1f)\n",
                    (unsigned int)hdr->srcNode, calculatedHops, (unsigned int)hdr->payloadLen, rssi, snr);

                  // Auto-reply ACK if requested
                  if (hdr->flags & OTA_FLAG_REQ_ACK) {
                    delay(40);
                    sendOtaAck(hdr->packetId, hdr->srcNode);
                  }

                  // Bridge to connected mobile phone via BLE Event Out notification
                  ble.sendRxMessage(hdr->srcNode, hdr->packetId, hdr->flags, rxBuffer + sizeof(OtaPacketHeader), hdr->payloadLen, rssi, snr);

                } else if (hdr->packetType == OTA_PKT_ACK) {
                  Serial.printf("[LORA RX ACK] Received Delivery ACK for Packet ID 0x%08X\n", (unsigned int)hdr->packetId);
                  uint32_t ackPktId = hdr->packetId;
                  ble.sendEvent(EVT_DELIVERY_ACK, 0, (const uint8_t*)&ackPktId, sizeof(ackPktId));
                }

              } else if (isBroadcast) {
                if (hdr->packetType == OTA_PKT_TEXT_MSG) {
                  Serial.printf("[LORA RX BCAST] From 0x%08X (Len: %u)\n",
                    (unsigned int)hdr->srcNode, (unsigned int)hdr->payloadLen);
                  ble.sendRxMessage(hdr->srcNode, hdr->packetId, hdr->flags | OTA_FLAG_BROADCAST, rxBuffer + sizeof(OtaPacketHeader), hdr->payloadLen, rssi, snr);
                } else if (hdr->packetType == OTA_PKT_NODE_ANNOUNCE) {
                  Serial.printf("[LORA RX ANNOUNCE] Node 0x%08X discovered (Hops: %u, RSSI: %.1f)\n",
                    (unsigned int)hdr->srcNode, calculatedHops, rssi);
                } else if (hdr->packetType == OTA_PKT_SOS) {
                  Serial.printf("[LORA RX SOS] !!! EMERGENCY SOS ALERT !!! From 0x%08X (Hops: %u, RSSI: %.1f)\n",
                    (unsigned int)hdr->srcNode, calculatedHops, rssi);
                  ble.sendRxMessage(hdr->srcNode, hdr->packetId, hdr->flags | OTA_FLAG_SOS, rxBuffer + sizeof(OtaPacketHeader), hdr->payloadLen, rssi, snr);
                }

                // Autonomous Broadcast Flood Relay (bounded by TTL & HopCount)
                if (hdr->ttl > 1 && hdr->hopCount < 5) {
                  relayPacket(rxBuffer, rxLen);
                }

              } else {
                // Unicast packet addressed to another node in the mesh -> Relay it!
                Serial.printf("[ROUTER] Packet 0x%08X addressed to 0x%08X (not us). Relaying...\n",
                  (unsigned int)hdr->packetId, (unsigned int)hdr->destNode);
                if (hdr->ttl > 1 && hdr->hopCount < 5) {
                  relayPacket(rxBuffer, rxLen);
                } else {
                  Serial.println(F("[ROUTER] TTL/Hop exhausted for unicast packet. Dropping."));
                }
              }
            }
          }
        } else {
          Serial.println(F("[LORA ERR] CRC Mismatch on received RF frame."));
        }
      }
    }

    radio.startReceive();
  }

  // Drain 1 queued outbound TX item per loop iteration (safe Core 1 SPI ownership)
  OutboundTxItem txItem;
  if (dequeueOtaTx(&txItem)) {
    bool ok = transmitOtaBuffer(txItem.data, txItem.len);
    if (txItem.notifyStatus) {
      ble.sendTxStatusForPacket(0, ok ? TX_STATUS_TRANSMITTED : TX_STATUS_FAILED, txItem.packetId);
    }
  }

  // Periodic Telemetry update to BLE (every 4 seconds)
  if (millis() - g_lastTelemetryTime >= 4000) {
    g_lastTelemetryTime = millis();
    int rssi = (int)radio.getRSSI();
    float snr = radio.getSNR();
    uint32_t batteryMv = 4120; // Nominal 4.12V LiPo battery
    ble.updateTelemetry(rssi, snr, (uint32_t)g_router.getNeighborCount(), millis() / 1000, batteryMv);
  }

  // Periodic Mesh Presence Announcement (every 60 seconds)
  if (millis() - g_lastAnnounceTime >= 60000) {
    g_lastAnnounceTime = millis();
    sendNodeAnnounce();
  }

  yield();
}
