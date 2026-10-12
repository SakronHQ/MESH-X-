/// MESH-X Bluetooth Low Energy Protocol Constants
/// Source of truth synchronized with docs/BLE_PROTOCOL.md and mesh_x_firmware/src/mesh_x_protocol.h
library;

class BleConstants {
  // Service and Characteristic UUIDs (128-bit custom)
  static const String serviceUuid = '4D455348-5800-0001-8000-00805F9B34FB';
  static const String charDeviceInfoUuid = '4D455348-5800-0002-8000-00805F9B34FB';
  static const String charCommandInUuid = '4D455348-5800-0003-8000-00805F9B34FB';
  static const String charEventOutUuid = '4D455348-5800-0004-8000-00805F9B34FB';
  static const String charTelemetryUuid = '4D455348-5800-0005-8000-00805F9B34FB';

  // Binary Framing
  static const int magicByte0 = 0xAA;
  static const int magicByte1 = 0x58; // ASCII 'X'
  static const int protocolVersion = 0x01;
  static const int maxPayloadSize = 256;

  // Command Codes (Mobile -> ESP32)
  static const int cmdSubmitMessage = 0x10;
  static const int cmdPing = 0x11;
  static const int cmdSetRadioConfig = 0x12;
  static const int cmdGetTelemetry = 0x13;
  static const int cmdSubmitSos = 0x14;

  // Event Codes (ESP32 -> Mobile)
  static const int evtRxMessage = 0x80;
  static const int evtTxStatus = 0x81;
  static const int evtDeliveryAck = 0x82;
  static const int evtPong = 0x83;
  static const int evtNodeDiscovered = 0x84;
  static const int evtError = 0x85;

  // SharedPreferences Keys
  static const String prefLastDeviceId = 'mesh_x_last_device_id';
  static const String prefAutoReconnect = 'mesh_x_auto_reconnect';
}
