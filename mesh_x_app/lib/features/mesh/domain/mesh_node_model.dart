class MeshNodeModel {
  final int nodeId;
  final String alias;
  final int hopDistance;
  final int lastRssi;
  final double lastSnr;
  final int lastSeenAt;

  const MeshNodeModel({
    required this.nodeId,
    required this.alias,
    required this.hopDistance,
    required this.lastRssi,
    required this.lastSnr,
    required this.lastSeenAt,
  });

  String get formattedNodeHex =>
      '0x${nodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';

  bool get isDirectNeighbor => hopDistance <= 1;

  String get relativeLastSeen {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - lastSeenAt;
    if (diff < 5) return 'Just now';
    if (diff < 60) return '${diff}s ago';
    if (diff < 3600) return '${diff ~/ 60}m ago';
    return '${diff ~/ 3600}h ago';
  }

  MeshNodeModel copyWith({
    int? nodeId,
    String? alias,
    int? hopDistance,
    int? lastRssi,
    double? lastSnr,
    int? lastSeenAt,
  }) {
    return MeshNodeModel(
      nodeId: nodeId ?? this.nodeId,
      alias: alias ?? this.alias,
      hopDistance: hopDistance ?? this.hopDistance,
      lastRssi: lastRssi ?? this.lastRssi,
      lastSnr: lastSnr ?? this.lastSnr,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'node_id': nodeId,
      'alias': alias,
      'hop_distance': hopDistance,
      'last_rssi': lastRssi,
      'last_snr': lastSnr,
      'last_seen_at': lastSeenAt,
    };
  }

  factory MeshNodeModel.fromMap(Map<String, dynamic> map) {
    return MeshNodeModel(
      nodeId: map['node_id'] as int,
      alias: map['alias'] as String? ??
          'Node 0x${(map['node_id'] as int).toRadixString(16).padLeft(8, '0').toUpperCase()}',
      hopDistance: (map['hop_distance'] as int?) ?? 1,
      lastRssi: (map['last_rssi'] as int?) ?? -100,
      lastSnr: (map['last_snr'] as num?)?.toDouble() ?? 0.0,
      lastSeenAt: map['last_seen_at'] as int,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeshNodeModel &&
          runtimeType == other.runtimeType &&
          nodeId == other.nodeId &&
          alias == other.alias &&
          hopDistance == other.hopDistance &&
          lastRssi == other.lastRssi &&
          lastSnr == other.lastSnr &&
          lastSeenAt == other.lastSeenAt;

  @override
  int get hashCode =>
      nodeId.hashCode ^
      alias.hashCode ^
      hopDistance.hashCode ^
      lastRssi.hashCode ^
      lastSnr.hashCode ^
      lastSeenAt.hashCode;
}
