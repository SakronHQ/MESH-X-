enum MessageDeliveryStatus {
  draft,
  queued,
  transmitted,
  delivered,
  failed;

  static MessageDeliveryStatus fromString(String val) {
    switch (val.toUpperCase()) {
      case 'QUEUED':
        return MessageDeliveryStatus.queued;
      case 'TRANSMITTED':
        return MessageDeliveryStatus.transmitted;
      case 'DELIVERED':
        return MessageDeliveryStatus.delivered;
      case 'FAILED':
        return MessageDeliveryStatus.failed;
      default:
        return MessageDeliveryStatus.draft;
    }
  }

  String toDbString() => name.toUpperCase();
}

class MessageModel {
  final String id;
  final int packetId;
  final String conversationId;
  final int senderNodeId;
  final int recipientNodeId;
  final String textContent;
  final MessageDeliveryStatus deliveryStatus;
  final bool isIncoming;
  final bool isEncrypted;
  final int retryCount;
  final int? rssi;
  final double? snr;
  final int hopCount;
  final int createdAt;
  final int? deliveredAt;

  const MessageModel({
    required this.id,
    required this.packetId,
    required this.conversationId,
    required this.senderNodeId,
    required this.recipientNodeId,
    required this.textContent,
    required this.deliveryStatus,
    required this.isIncoming,
    this.isEncrypted = false,
    this.retryCount = 0,
    this.rssi,
    this.snr,
    this.hopCount = 0,
    required this.createdAt,
    this.deliveredAt,
  });

  MessageModel copyWith({
    String? id,
    int? packetId,
    String? conversationId,
    int? senderNodeId,
    int? recipientNodeId,
    String? textContent,
    MessageDeliveryStatus? deliveryStatus,
    bool? isIncoming,
    bool? isEncrypted,
    int? retryCount,
    int? rssi,
    double? snr,
    int? hopCount,
    int? createdAt,
    int? deliveredAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      packetId: packetId ?? this.packetId,
      conversationId: conversationId ?? this.conversationId,
      senderNodeId: senderNodeId ?? this.senderNodeId,
      recipientNodeId: recipientNodeId ?? this.recipientNodeId,
      textContent: textContent ?? this.textContent,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      isIncoming: isIncoming ?? this.isIncoming,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      retryCount: retryCount ?? this.retryCount,
      rssi: rssi ?? this.rssi,
      snr: snr ?? this.snr,
      hopCount: hopCount ?? this.hopCount,
      createdAt: createdAt ?? this.createdAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'packet_id': packetId,
      'conversation_id': conversationId,
      'sender_node_id': senderNodeId,
      'recipient_node_id': recipientNodeId,
      'text_content': textContent,
      'delivery_status': deliveryStatus.toDbString(),
      'is_incoming': isIncoming ? 1 : 0,
      'is_encrypted': isEncrypted ? 1 : 0,
      'retry_count': retryCount,
      'rssi': rssi,
      'snr': snr,
      'hop_count': hopCount,
      'created_at': createdAt,
      'delivered_at': deliveredAt,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      packetId: map['packet_id'] as int,
      conversationId: map['conversation_id'] as String,
      senderNodeId: map['sender_node_id'] as int,
      recipientNodeId: map['recipient_node_id'] as int,
      textContent: map['text_content'] as String,
      deliveryStatus: MessageDeliveryStatus.fromString(map['delivery_status'] as String),
      isIncoming: (map['is_incoming'] as int) == 1,
      isEncrypted: (map['is_encrypted'] as int? ?? 0) == 1,
      retryCount: map['retry_count'] as int? ?? 0,
      rssi: map['rssi'] as int?,
      snr: (map['snr'] as num?)?.toDouble(),
      hopCount: map['hop_count'] as int? ?? 0,
      createdAt: map['created_at'] as int,
      deliveredAt: map['delivered_at'] as int?,
    );
  }
}
