class SosAlertModel {
  final int packetId;
  final int senderNodeId;
  final double? latitude;
  final double? longitude;
  final String distressMessage;
  final int timestamp;
  final int? rssi;
  final double? snr;

  const SosAlertModel({
    required this.packetId,
    required this.senderNodeId,
    this.latitude,
    this.longitude,
    required this.distressMessage,
    required this.timestamp,
    this.rssi,
    this.snr,
  });

  String get formattedNodeHex =>
      '0x${senderNodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  bool get hasLocation =>
      latitude != null &&
      longitude != null &&
      (latitude != 0.0 || longitude != 0.0);

  String get locationString => hasLocation
      ? '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}'
      : 'No GPS Location Attached';

  SosAlertModel copyWith({
    int? packetId,
    int? senderNodeId,
    double? latitude,
    double? longitude,
    String? distressMessage,
    int? timestamp,
    int? rssi,
    double? snr,
  }) {
    return SosAlertModel(
      packetId: packetId ?? this.packetId,
      senderNodeId: senderNodeId ?? this.senderNodeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distressMessage: distressMessage ?? this.distressMessage,
      timestamp: timestamp ?? this.timestamp,
      rssi: rssi ?? this.rssi,
      snr: snr ?? this.snr,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packet_id': packetId,
      'sender_node_id': senderNodeId,
      'latitude': latitude,
      'longitude': longitude,
      'distress_message': distressMessage,
      'timestamp': timestamp,
      'rssi': rssi,
      'snr': snr,
    };
  }

  factory SosAlertModel.fromMap(Map<String, dynamic> map) {
    return SosAlertModel(
      packetId: map['packet_id'] as int,
      senderNodeId: map['sender_node_id'] as int,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      distressMessage: map['distress_message'] as String,
      timestamp: map['timestamp'] as int,
      rssi: map['rssi'] as int?,
      snr: (map['snr'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SosAlertModel &&
          runtimeType == other.runtimeType &&
          packetId == other.packetId &&
          senderNodeId == other.senderNodeId &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          distressMessage == other.distressMessage &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      packetId.hashCode ^
      senderNodeId.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      distressMessage.hashCode ^
      timestamp.hashCode;
}
