#pragma once

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "mesh_x_protocol.h"

typedef void (*MessageSubmitCallback)(const uint8_t* payload, size_t len);
typedef void (*SosSubmitCallback)(const uint8_t* payload, size_t len);

class MeshXBLE : public BLEServerCallbacks, public BLECharacteristicCallbacks {
public:
  MeshXBLE()
    : m_nodeId(0),
      m_fwVersion("1.0.0"),
      m_deviceConnected(false),
      m_oldDeviceConnected(false),
      m_outboundSeq(0),
      m_pServer(nullptr),
      m_pDeviceInfoChar(nullptr),
      m_pCommandInChar(nullptr),
      m_pEventOutChar(nullptr),
      m_pTelemetryChar(nullptr),
      m_msgCb(nullptr),
      m_sosCb(nullptr) {
  }

  bool begin(uint32_t nodeId, const String& fwVersion = "1.0.0") {
    m_nodeId = nodeId;
    m_fwVersion = fwVersion;

    char devName[32];
    snprintf(devName, sizeof(devName), "MESH-X-%06X", (unsigned int)(nodeId & 0xFFFFFF));

    Serial.printf("[BLE] Initializing BLE GATT Server as \"%s\"...\n", devName);
    BLEDevice::init(devName);
    BLEDevice::setMTU(256);

    // 1. Create Server
    m_pServer = BLEDevice::createServer();
    m_pServer->setCallbacks(this);

    // 2. Create Primary Service
    BLEService* pService = m_pServer->createService(MESHX_SERVICE_UUID);

    // 3. Create Characteristics
    // Device Info (Read)
    m_pDeviceInfoChar = pService->createCharacteristic(
      MESHX_CHAR_DEVICE_INFO_UUID,
      BLECharacteristic::PROPERTY_READ
    );

    // Command In (Write / Write Without Response)
    m_pCommandInChar = pService->createCharacteristic(
      MESHX_CHAR_COMMAND_IN_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
    );
    m_pCommandInChar->setCallbacks(this);

    // Event Out (Notify)
    m_pEventOutChar = pService->createCharacteristic(
      MESHX_CHAR_EVENT_OUT_UUID,
      BLECharacteristic::PROPERTY_NOTIFY
    );
    m_pEventOutChar->addDescriptor(new BLE2902());

    // Telemetry (Read / Notify)
    m_pTelemetryChar = pService->createCharacteristic(
      MESHX_CHAR_TELEMETRY_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
    );
    m_pTelemetryChar->addDescriptor(new BLE2902());

    // Populate initial values
    updateDeviceInfo();
    updateTelemetry(0, 0.0f, 0, 0);

    // 4. Start Service
    pService->start();

    // 5. Start Advertising
    BLEAdvertising* pAdv = BLEDevice::getAdvertising();
    pAdv->addServiceUUID(MESHX_SERVICE_UUID);
    pAdv->setScanResponse(true);
    pAdv->setMinPreferred(0x06);
    pAdv->setMaxPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println(F("[BLE] Advertising started. Waiting for mobile app connection."));
    return true;
  }

  void loop() {
    // Handle disconnection recovery and restart advertising
    if (!m_deviceConnected && m_oldDeviceConnected) {
      delay(300);
      m_pServer->startAdvertising();
      Serial.println(F("[BLE] Client disconnected. Advertising resumed."));
      m_oldDeviceConnected = m_deviceConnected;
    }
    if (m_deviceConnected && !m_oldDeviceConnected) {
      m_oldDeviceConnected = m_deviceConnected;
    }
  }

  bool isConnected() const { return m_deviceConnected; }
  uint32_t getNodeId() const { return m_nodeId; }

  void onMessageSubmitted(MessageSubmitCallback cb) { m_msgCb = cb; }
  void onSosSubmitted(SosSubmitCallback cb) { m_sosCb = cb; }

  void updateDeviceInfo() {
    if (!m_pDeviceInfoChar) return;
    char infoJson[160];
    snprintf(infoJson, sizeof(infoJson),
      "{\"node_id\":%u,\"fw\":\"%s\",\"proto\":%u,\"name\":\"MESH-X-%06X\"}",
      (unsigned int)m_nodeId,
      m_fwVersion.c_str(),
      BLE_FRAME_VERSION,
      (unsigned int)(m_nodeId & 0xFFFFFF)
    );
    m_pDeviceInfoChar->setValue((uint8_t*)infoJson, strlen(infoJson));
  }

  bool updateTelemetry(int rssi, float snr, uint32_t queueDepth, uint32_t uptimeSec, uint32_t batteryMv = 4120) {
    if (!m_pTelemetryChar) return false;
    char teleJson[160];
    snprintf(teleJson, sizeof(teleJson),
      "{\"rssi\":%d,\"snr\":%.1f,\"queue\":%u,\"uptime\":%u,\"batt\":%u}",
      rssi, snr, (unsigned int)queueDepth, (unsigned int)uptimeSec, (unsigned int)batteryMv
    );
    m_pTelemetryChar->setValue((uint8_t*)teleJson, strlen(teleJson));
    if (m_deviceConnected) {
      m_pTelemetryChar->notify();
    }
    return true;
  }

  bool sendEvent(uint8_t eventType, uint16_t seqNum, const uint8_t* payload, size_t len) {
    if (!m_deviceConnected || !m_pEventOutChar) return false;

    size_t totalFrameLen = sizeof(BleFrameHeader) + len + 2;
    if (totalFrameLen > BLE_MAX_PAYLOAD_SIZE) {
      Serial.println(F("[BLE ERR] Outbound event exceeds buffer size."));
      return false;
    }

    uint8_t buffer[BLE_MAX_PAYLOAD_SIZE];
    BleFrameHeader* hdr = reinterpret_cast<BleFrameHeader*>(buffer);
    hdr->magic0 = BLE_FRAME_MAGIC_BYTE0;
    hdr->magic1 = BLE_FRAME_MAGIC_BYTE1;
    hdr->version = BLE_FRAME_VERSION;
    hdr->frameType = eventType;
    hdr->seqNum = seqNum;
    hdr->totalPayloadLen = (uint16_t)len;
    hdr->fragIndex = 0;
    hdr->fragCount = 1;

    if (len > 0 && payload != nullptr) {
      memcpy(buffer + sizeof(BleFrameHeader), payload, len);
    }

    uint16_t crc = computeCrc16(buffer, sizeof(BleFrameHeader) + len);
    buffer[sizeof(BleFrameHeader) + len] = (uint8_t)(crc & 0xFF);
    buffer[sizeof(BleFrameHeader) + len + 1] = (uint8_t)((crc >> 8) & 0xFF);

    m_pEventOutChar->setValue(buffer, totalFrameLen);
    m_pEventOutChar->notify();
    return true;
  }

  bool sendError(uint16_t seqNum, uint8_t errorCode) {
    uint8_t payload[2] = { (uint8_t)(seqNum & 0xFF), errorCode };
    return sendEvent(EVT_ERROR, seqNum, payload, sizeof(payload));
  }

  bool sendTxStatus(uint16_t seqNum, uint8_t status) {
    uint8_t payload[2] = { (uint8_t)(seqNum & 0xFF), status };
    return sendEvent(EVT_TX_STATUS, seqNum, payload, sizeof(payload));
  }

  bool sendRxMessage(uint32_t srcNode, uint8_t flags, const uint8_t* msgBytes, size_t msgLen, float rssi, float snr) {
    if (!m_deviceConnected) return false;
    size_t payloadLen = 4 + 1 + 1 + 1 + msgLen;
    if (payloadLen > BLE_MAX_PAYLOAD_SIZE) return false;
    uint8_t payload[BLE_MAX_PAYLOAD_SIZE];

    memcpy(payload, &srcNode, 4);
    payload[4] = (int8_t)rssi;
    payload[5] = (int8_t)snr;
    payload[6] = flags;
    if (msgLen > 0 && msgBytes != nullptr) {
      memcpy(payload + 7, msgBytes, msgLen);
    }

    m_outboundSeq++;
    return sendEvent(EVT_RX_MESSAGE, m_outboundSeq, payload, payloadLen);
  }

  bool sendRxMessage(uint32_t srcNode, const String& text, float rssi, float snr) {
    return sendRxMessage(srcNode, 0, (const uint8_t*)text.c_str(), text.length(), rssi, snr);
  }

  bool sendNodeDiscovered(uint32_t nodeId, uint8_t hops, float rssi, float snr) {
    if (!m_deviceConnected) return false;
    uint8_t payload[7];
    memcpy(payload, &nodeId, 4);
    payload[4] = hops;
    payload[5] = (int8_t)rssi;
    payload[6] = (int8_t)snr;
    m_outboundSeq++;
    return sendEvent(EVT_NODE_DISCOVERED, m_outboundSeq, payload, sizeof(payload));
  }

  // BLEServerCallbacks
  void onConnect(BLEServer* pServer) override {
    m_deviceConnected = true;
    Serial.println(F("[BLE] Mobile client connected!"));
  }

  void onDisconnect(BLEServer* pServer) override {
    m_deviceConnected = false;
  }

  // BLECharacteristicCallbacks
  void onWrite(BLECharacteristic* pCharacteristic) override {
    const uint8_t* pData = pCharacteristic->getData();
    size_t len = pCharacteristic->getLength();

    if (len < sizeof(BleFrameHeader) + 2) {
      Serial.printf("[BLE] Frame too small (%d bytes), discarded.\n", (int)len);
      sendError(0, ERR_INVALID_MAGIC);
      return;
    }

    const BleFrameHeader* hdr = reinterpret_cast<const BleFrameHeader*>(pData);

    // 1. Validate Magic bytes
    if (hdr->magic0 != BLE_FRAME_MAGIC_BYTE0 || hdr->magic1 != BLE_FRAME_MAGIC_BYTE1) {
      Serial.printf("[BLE] Invalid magic (0x%02X 0x%02X), discarded.\n", hdr->magic0, hdr->magic1);
      sendError(hdr->seqNum, ERR_INVALID_MAGIC);
      return;
    }

    // 2. Validate CRC16
    size_t payloadLen = len - sizeof(BleFrameHeader) - 2;
    uint16_t expectedCrc = computeCrc16(pData, len - 2);
    uint16_t receivedCrc = (uint16_t)pData[len - 2] | ((uint16_t)pData[len - 1] << 8);

    if (expectedCrc != receivedCrc) {
      Serial.printf("[BLE] CRC mismatch: exp 0x%04X != rx 0x%04X\n", expectedCrc, receivedCrc);
      sendError(hdr->seqNum, ERR_CRC_MISMATCH);
      return;
    }

    // 3. Process Command
    const uint8_t* payloadPtr = pData + sizeof(BleFrameHeader);
    processCommand(hdr->frameType, hdr->seqNum, payloadPtr, payloadLen);
  }

private:
  uint32_t m_nodeId;
  String   m_fwVersion;
  bool     m_deviceConnected;
  bool     m_oldDeviceConnected;
  uint16_t m_outboundSeq;

  BLEServer*         m_pServer;
  BLECharacteristic* m_pDeviceInfoChar;
  BLECharacteristic* m_pCommandInChar;
  BLECharacteristic* m_pEventOutChar;
  BLECharacteristic* m_pTelemetryChar;

  MessageSubmitCallback m_msgCb;
  SosSubmitCallback     m_sosCb;

  void processCommand(uint8_t cmdType, uint16_t seqNum, const uint8_t* payload, size_t len) {
    Serial.printf("[BLE CMD] Type: 0x%02X | Seq: %u | Payload: %d B\n", cmdType, seqNum, (int)len);

    switch (cmdType) {
      case CMD_PING: {
        Serial.println(F("[BLE CMD] PING received! Replying with PONG."));
        uint32_t nowMs = millis();
        sendEvent(EVT_PONG, seqNum, (const uint8_t*)&nowMs, sizeof(nowMs));
        break;
      }

      case CMD_SUBMIT_MESSAGE: {
        Serial.println(F("[BLE CMD] SUBMIT_MESSAGE received."));
        sendTxStatus(seqNum, TX_STATUS_QUEUED);
        if (m_msgCb) {
          m_msgCb(payload, len);
        }
        break;
      }

      case CMD_SUBMIT_SOS: {
        Serial.println(F("[BLE CMD] SUBMIT_SOS received!"));
        sendTxStatus(seqNum, TX_STATUS_QUEUED);
        if (m_sosCb) {
          m_sosCb(payload, len);
        }
        break;
      }

      case CMD_GET_TELEMETRY: {
        updateTelemetry(0, 0.0f, 0, millis() / 1000);
        break;
      }

      default:
        Serial.printf("[BLE WARN] Unknown command 0x%02X\n", cmdType);
        sendError(seqNum, ERR_UNKNOWN_CMD);
        break;
    }
  }
};
