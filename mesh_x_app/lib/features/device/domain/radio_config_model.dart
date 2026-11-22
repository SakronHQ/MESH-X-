import 'dart:math';
import 'dart:typed_data';

/// LoRa RF Configuration settings for the connected ESP32 node.
class RadioConfigModel {
  final double frequencyMhz;
  final int spreadingFactor;
  final double bandwidthKhz;
  final int codingRate;
  final int txPowerDbm;

  const RadioConfigModel({
    this.frequencyMhz = 433.175,
    this.spreadingFactor = 9,
    this.bandwidthKhz = 125.0,
    this.codingRate = 7,
    this.txPowerDbm = 14,
  });

  /// Binary wire serialization for CMD_SET_RADIO_CONFIG (0x12)
  /// [FREQ_KHZ: 4B LE][SF: 1B][BW_KHZ: 2B LE][CR: 1B][TX_POWER: 1B] = 9 bytes total
  Uint8List toBytes() {
    final buffer = Uint8List(9);
    final bd = ByteData.sublistView(buffer);
    final freqKhz = (frequencyMhz * 1000).round();
    bd.setUint32(0, freqKhz, Endian.little);
    bd.setUint8(4, spreadingFactor.clamp(7, 12));
    bd.setUint16(5, bandwidthKhz.round(), Endian.little);
    bd.setUint8(7, codingRate.clamp(5, 8));
    bd.setInt8(8, txPowerDbm.clamp(2, 20));
    return buffer;
  }

  factory RadioConfigModel.fromBytes(Uint8List bytes) {
    if (bytes.length < 9) {
      throw ArgumentError('RadioConfig bytes must be at least 9 bytes');
    }
    final bd = ByteData.sublistView(bytes);
    final freqKhz = bd.getUint32(0, Endian.little);
    final sf = bd.getUint8(4);
    final bwKhz = bd.getUint16(5, Endian.little);
    final cr = bd.getUint8(7);
    final txPower = bd.getInt8(8);

    return RadioConfigModel(
      frequencyMhz: freqKhz / 1000.0,
      spreadingFactor: sf,
      bandwidthKhz: bwKhz.toDouble(),
      codingRate: cr,
      txPowerDbm: txPower,
    );
  }

  RadioConfigModel copyWith({
    double? frequencyMhz,
    int? spreadingFactor,
    double? bandwidthKhz,
    int? codingRate,
    int? txPowerDbm,
  }) {
    return RadioConfigModel(
      frequencyMhz: frequencyMhz ?? this.frequencyMhz,
      spreadingFactor: spreadingFactor ?? this.spreadingFactor,
      bandwidthKhz: bandwidthKhz ?? this.bandwidthKhz,
      codingRate: codingRate ?? this.codingRate,
      txPowerDbm: txPowerDbm ?? this.txPowerDbm,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'frequency_mhz': frequencyMhz,
      'spreading_factor': spreadingFactor,
      'bandwidth_khz': bandwidthKhz,
      'coding_rate': codingRate,
      'tx_power_dbm': txPowerDbm,
    };
  }

  factory RadioConfigModel.fromMap(Map<String, dynamic> map) {
    return RadioConfigModel(
      frequencyMhz: (map['frequency_mhz'] as num?)?.toDouble() ?? 433.175,
      spreadingFactor: (map['spreading_factor'] as int?) ?? 9,
      bandwidthKhz: (map['bandwidth_khz'] as num?)?.toDouble() ?? 125.0,
      codingRate: (map['coding_rate'] as int?) ?? 7,
      txPowerDbm: (map['tx_power_dbm'] as int?) ?? 14,
    );
  }

  /// Calculates estimated transmission time on air (ToA) in ms for a standard mesh packet
  int estimateTimeToAirMs({int payloadBytes = 32}) {
    // Basic LoRa symbol duration: Ts = 2^SF / BW
    final symbolDurationMs = (1 << spreadingFactor) / bandwidthKhz;
    // Preamble symbols = 8 + 4.25 = 12.25
    final preambleDuration = 12.25 * symbolDurationMs;
    // Payload symbol count estimate (Semtech SX1278 explicit header with CRC)
    final rawSymbolCount = ((8 * payloadBytes - 4 * spreadingFactor + 28) / (4 * spreadingFactor)).ceil();
    final payloadSymbols = 8 + (max(0, rawSymbolCount) * codingRate);
    final totalDuration = preambleDuration + (payloadSymbols * symbolDurationMs);
    return totalDuration.round().clamp(10, 5000);
  }

  /// Human-friendly mode description
  String get speedModeDescription {
    if (spreadingFactor <= 7) return 'Fast / Short Range (Low Latency)';
    if (spreadingFactor <= 9) return 'Balanced Mesh (Recommended)';
    if (spreadingFactor <= 10) return 'Long Range (High Penetration)';
    return 'Extreme Distance (Maximum Link Budget)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadioConfigModel &&
          runtimeType == other.runtimeType &&
          frequencyMhz == other.frequencyMhz &&
          spreadingFactor == other.spreadingFactor &&
          bandwidthKhz == other.bandwidthKhz &&
          codingRate == other.codingRate &&
          txPowerDbm == other.txPowerDbm;

  @override
  int get hashCode =>
      frequencyMhz.hashCode ^
      spreadingFactor.hashCode ^
      bandwidthKhz.hashCode ^
      codingRate.hashCode ^
      txPowerDbm.hashCode;
}
