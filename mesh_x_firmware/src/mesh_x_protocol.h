#pragma once

#include <Arduino.h>

// =============================================================================
// MESH-X BLE 128-BIT GATT UUIDS
// Base: 4D455348-5800-xxxx-8000-00805F9B34FB ("MESH-X")
// =============================================================================
#define MESHX_SERVICE_UUID           "4D455348-5800-0001-8000-00805F9B34FB"
#define MESHX_CHAR_DEVICE_INFO_UUID  "4D455348-5800-0002-8000-00805F9B34FB"
#define MESHX_CHAR_COMMAND_IN_UUID   "4D455348-5800-0003-8000-00805F9B34FB"
#define MESHX_CHAR_EVENT_OUT_UUID    "4D455348-5800-0004-8000-00805F9B34FB"
#define MESHX_CHAR_TELEMETRY_UUID    "4D455348-5800-0005-8000-00805F9B34FB"

// =============================================================================
// BLE FRAMING CONSTANTS
// =============================================================================
#define BLE_FRAME_MAGIC_BYTE0        0xAA
#define BLE_FRAME_MAGIC_BYTE1        0x58  // 'X'
#define BLE_FRAME_VERSION            0x01

#define BLE_MAX_PAYLOAD_SIZE         256
#define BLE_REASSEMBLY_TIMEOUT_MS    3000

// Command Codes (Mobile -> ESP32)
#define CMD_SUBMIT_MESSAGE           0x10
#define CMD_PING                     0x11
#define CMD_SET_RADIO_CONFIG         0x12
#define CMD_GET_TELEMETRY            0x13
#define CMD_SUBMIT_SOS               0x14

// Event Codes (ESP32 -> Mobile)
#define EVT_RX_MESSAGE               0x80
#define EVT_TX_STATUS                0x81
#define EVT_DELIVERY_ACK             0x82
#define EVT_PONG                     0x83
#define EVT_NODE_DISCOVERED          0x84
#define EVT_ERROR                    0x85

// Error Codes
#define ERR_NONE                     0x00
#define ERR_INVALID_MAGIC            0x01
#define ERR_CRC_MISMATCH             0x02
#define ERR_UNKNOWN_CMD              0x03
#define ERR_PAYLOAD_TOO_LARGE        0x04
#define ERR_RADIO_BUSY               0x05
#define ERR_RADIO_FAULT              0x06
#define ERR_TIMEOUT                  0x07

// TX Status Values
#define TX_STATUS_QUEUED             0x01
#define TX_STATUS_TRANSMITTED        0x02
#define TX_STATUS_FAILED             0x03

#pragma pack(push, 1)
struct BleFrameHeader {
  uint8_t  magic0;          // 0xAA
  uint8_t  magic1;          // 0x58
  uint8_t  version;         // 0x01
  uint8_t  frameType;       // CMD_* or EVT_*
  uint16_t seqNum;          // Frame sequence number
  uint16_t totalPayloadLen; // Complete payload length across all fragments
  uint8_t  fragIndex;       // 0-indexed fragment number
  uint8_t  fragCount;       // Total fragments
};
#pragma pack(pop)

// CRC-16-CCITT calculation (Polynomial: 0x1021, Initial: 0xFFFF)
inline uint16_t computeCrc16(const uint8_t* data, size_t length) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < length; ++i) {
    crc ^= (uint16_t)data[i] << 8;
    for (uint8_t bit = 0; bit < 8; ++bit) {
      if (crc & 0x8000) {
        crc = (crc << 1) ^ 0x1021;
      } else {
        crc <<= 1;
      }
    }
  }
  return crc;
}
