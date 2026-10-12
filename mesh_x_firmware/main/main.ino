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

// BLE Server instance
MeshXBLE ble;

// Mesh Router instance
MeshRouter g_router;

// Node Identity & Globals
uint32_t g_localNodeId = 0;
volatile bool g_radioDio0Triggered = false;
uint32_t g_lastTelemetryTime = 0;
uint32_t g_lastAnnounceTime = 0;

// Radio packet types (OTA)
#define OTA_PKT_TEXT_MSG       0x01
#define OTA_PKT_ACK            0x02
#define OTA_PKT_NODE_ANNOUNCE  0x03

#define OTA_FLAG_REQ_ACK       0x01

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

// Transmit an over-the-air raw buffer
bool transmitOtaBuffer(const uint8_t* buffer, size_t totalLen) {
  g_radioDio0Triggered = false;
  int16_t state = radio.startTransmit((uint8_t*)buffer, totalLen);
  if (state == RADIOLIB_ERR_NONE) {
    uint32_t startMs = millis();
    while (!g_radioDio0Triggered && (millis() - startMs < 1200)) {
      yield();
    }
  } else {
    Serial.printf("[RADIO TX ERR] startTransmit code: %d\n", state);
  }

  // Restore non-blocking receive mode
  g_radioDio0Triggered = false;
  radio.startReceive();
  return (state == RADIOLIB_ERR_NONE);
}

// Relay an over-the-air packet across the mesh
void relayPacket(const uint8_t* originalPacket, size_t packetLen) {
  if (packetLen < sizeof(OtaPacketHeader) + 2 || packetLen > 256) return;

  uint8_t relayBuf[256];
  memcpy(relayBuf, originalPacket, packetLen);
  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(relayBuf);

  if (hdr->ttl <= 1) {
    Serial.printf("[ROUTER] TTL expired for packet 0x%08X. Dropping.\n", (unsigned int)hdr->packetId);
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
  hdr->ttl = 3;
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
  g_router.isDuplicate(hdr->packetId);

  uint16_t crc = computeCrc16(buf, sizeof(OtaPacketHeader));
  buf[sizeof(OtaPacketHeader)] = (uint8_t)(crc & 0xFF);
  buf[sizeof(OtaPacketHeader) + 1] = (uint8_t)((crc >> 8) & 0xFF);

  Serial.printf("[MESH ANNOUNCE] Broadcasting node presence (Node 0x%08X)\n", (unsigned int)g_localNodeId);
  transmitOtaBuffer(buf, sizeof(buf));
}

// Callback invoked when mobile app submits message via BLE
void onMobileMessageSubmitted(const uint8_t* payload, size_t len) {
  // Expected payload: [PACKET_ID: 4B][DEST_NODE: 4B][FLAGS: 1B][TEXT]
  if (len < 9) {
    Serial.println(F("[BRIDGE ERR] Submitted message payload too short."));
    return;
  }

  uint32_t packetId = *reinterpret_cast<const uint32_t*>(payload);
  uint32_t destNode = *reinterpret_cast<const uint32_t*>(payload + 4);
  uint8_t flags     = payload[8];
  const char* text  = reinterpret_cast<const char*>(payload + 9);
  size_t textLen    = len - 9;

  Serial.printf("[BRIDGE] Outbound Msg from Mobile: PktID 0x%08X -> Dest 0x%08X (len %d)\n",
    (unsigned int)packetId, (unsigned int)destNode, (int)textLen);

  // Suppress our own outbound packet from being relayed back to us
  g_router.isDuplicate(packetId);

  // Build OTA Frame
  size_t otaTotalLen = sizeof(OtaPacketHeader) + textLen + 2;
  uint8_t otaBuf[256];
  if (otaTotalLen > sizeof(otaBuf)) {
    Serial.println(F("[BRIDGE ERR] Message exceeds RF packet limit."));
    return;
  }

  OtaPacketHeader* hdr = reinterpret_cast<OtaPacketHeader*>(otaBuf);
  hdr->magic = MESH_MAGIC_BYTE;
  hdr->version = MESH_PROTO_VERSION;
  hdr->packetType = OTA_PKT_TEXT_MSG;
  hdr->flags = flags;
  hdr->ttl = 3;
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

  // Transmit over LoRa
  bool ok = transmitOtaBuffer(otaBuf, otaTotalLen);

  // Notify mobile app that packet transmission finished
  ble.sendTxStatus(0, ok ? TX_STATUS_TRANSMITTED : TX_STATUS_FAILED);
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
    Serial.println(F("[INIT] SX1278 LoRa transceiver initialized successfully."));
  } else {
    Serial.printf("[INIT WARN] SX1278 init returned code %d. Verify SPI wiring & 3.3V.\n", radioState);
  }

  radio.setDio0Action(onRadioDio0, RISING);
  radio.startReceive();

  // 3. Initialize BLE GATT Server
  ble.onMessageSubmitted(onMobileMessageSubmitted);
  ble.begin(g_localNodeId, "1.1.0");
  Serial.println(F("[INIT] BLE, LoRa Radio and Mesh Router initialized.\n"));
}

void loop() {
  ble.loop();

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

          if (hdr->magic == MESH_MAGIC_BYTE) {
            // 1. Duplicate check (LRU ring buffer suppression)
            if (g_router.isDuplicate(hdr->packetId)) {
              Serial.printf("[ROUTER] Dropping duplicate packet 0x%08X\n", (unsigned int)hdr->packetId);
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
                  String text = "";
                  for (size_t i = 0; i < hdr->payloadLen; ++i) {
                    text += (char)rxBuffer[sizeof(OtaPacketHeader) + i];
                  }

                  Serial.printf("[LORA RX] Direct Msg from 0x%08X (Hops: %u): \"%s\" (RSSI: %.1f, SNR: %.1f)\n",
                    (unsigned int)hdr->srcNode, calculatedHops, text.c_str(), rssi, snr);

                  // Auto-reply ACK if requested
                  if (hdr->flags & OTA_FLAG_REQ_ACK) {
                    delay(40);
                    sendOtaAck(hdr->packetId, hdr->srcNode);
                  }

                  // Bridge to connected mobile phone via BLE Event Out notification
                  ble.sendRxMessage(hdr->srcNode, text, rssi, snr);

                } else if (hdr->packetType == OTA_PKT_ACK) {
                  Serial.printf("[LORA RX ACK] Received Delivery ACK for Packet ID 0x%08X\n", (unsigned int)hdr->packetId);
                  uint32_t ackPktId = hdr->packetId;
                  ble.sendEvent(EVT_DELIVERY_ACK, 0, (const uint8_t*)&ackPktId, sizeof(ackPktId));
                }

              } else if (isBroadcast) {
                if (hdr->packetType == OTA_PKT_TEXT_MSG) {
                  String text = "";
                  for (size_t i = 0; i < hdr->payloadLen; ++i) {
                    text += (char)rxBuffer[sizeof(OtaPacketHeader) + i];
                  }

                  Serial.printf("[LORA RX BCAST] From 0x%08X: \"%s\"\n", (unsigned int)hdr->srcNode, text.c_str());
                  ble.sendRxMessage(hdr->srcNode, text, rssi, snr);
                } else if (hdr->packetType == OTA_PKT_NODE_ANNOUNCE) {
                  Serial.printf("[LORA RX ANNOUNCE] Node 0x%08X discovered (Hops: %u, RSSI: %.1f)\n",
                    (unsigned int)hdr->srcNode, calculatedHops, rssi);
                }

                // Autonomous Broadcast Flood Relay (if TTL > 1)
                if (hdr->ttl > 1) {
                  relayPacket(rxBuffer, rxLen);
                }

              } else {
                // Unicast packet addressed to another node in the mesh -> Relay it!
                Serial.printf("[ROUTER] Packet 0x%08X addressed to 0x%08X (not us). Relaying...\n",
                  (unsigned int)hdr->packetId, (unsigned int)hdr->destNode);
                if (hdr->ttl > 1) {
                  relayPacket(rxBuffer, rxLen);
                } else {
                  Serial.println(F("[ROUTER] TTL exhausted for unicast packet. Dropping."));
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

  // Periodic Telemetry update to BLE (every 4 seconds)
  if (millis() - g_lastTelemetryTime >= 4000) {
    g_lastTelemetryTime = millis();
    int rssi = (int)radio.getRSSI();
    float snr = radio.getSNR();
    ble.updateTelemetry(rssi, snr, (uint32_t)g_router.getNeighborCount(), millis() / 1000);
  }

  // Periodic Mesh Presence Announcement (every 60 seconds)
  if (millis() - g_lastAnnounceTime >= 60000) {
    g_lastAnnounceTime = millis();
    sendNodeAnnounce();
  }

  yield();
}
