import 'dart:typed_data';

/// CRC-16-CCITT implementation (Polynomial: 0x1021, Initial: 0xFFFF)
/// Synchronized with firmware computeCrc16() in mesh_x_protocol.h
class Crc16 {
  static int compute(Uint8List data, [int? length]) {
    int len = length ?? data.length;
    int crc = 0xFFFF;
    for (int i = 0; i < len; ++i) {
      crc ^= (data[i] << 8) & 0xFFFF;
      for (int bit = 0; bit < 8; ++bit) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}
