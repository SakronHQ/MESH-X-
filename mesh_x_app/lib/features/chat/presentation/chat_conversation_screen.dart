import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../device/domain/connection_state.dart';
import '../../device/presentation/ble_controller.dart';
import '../domain/conversation_model.dart';
import '../domain/message_model.dart';
import '../../mesh/presentation/key_exchange_dialog.dart';
import 'chat_controller.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  final ConversationModel conversation;

  const ChatConversationScreen({super.key, required this.conversation});

  @override
  ConsumerState<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends ConsumerState<ChatConversationScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isComposing = false;
  static const int _maxChars = 180;

  @override
  void initState() {
    super.initState();
    _textController.addListener(() {
      final isComp = _textController.text.trim().isNotEmpty;
      if (isComp != _isComposing) {
        setState(() => _isComposing = isComp);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    final bleState = ref.read(bleControllerProvider);
    final localNodeId = bleState.deviceInfo?.nodeId ?? 0;
    final chatRepo = ref.read(chatRepositoryProvider);

    await chatRepo.sendMessage(
      conversationId: widget.conversation.id,
      recipientNodeId: widget.conversation.peerNodeId,
      textContent: text,
      localNodeId: localNodeId,
    );

    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleControllerProvider);
    final isConnected = bleState.status == BleConnectionStatus.connected;
    final messagesAsync = ref.watch(messagesProvider(widget.conversation.id));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.conversation.title, style: const TextStyle(fontSize: 16)),
            Text(
              widget.conversation.formattedPeerHex,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          if (widget.conversation.peerNodeId != 0xFFFFFFFF)
            IconButton(
              icon: FutureBuilder<String?>(
                future: ref
                    .watch(chatRepositoryProvider)
                    .getPeerPublicKey(widget.conversation.peerNodeId),
                builder: (context, snapshot) {
                  final isPaired = snapshot.hasData &&
                      snapshot.data != null &&
                      snapshot.data!.length == 64;
                  return Icon(
                    isPaired ? Icons.lock : Icons.lock_open,
                    color: isPaired ? AppColors.connected : AppColors.textMuted,
                    size: 20,
                  );
                },
              ),
              tooltip: 'End-to-End Encryption Keys',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => KeyExchangeDialog(
                    peerNodeId: widget.conversation.peerNodeId,
                  ),
                ).then((_) => setState(() {}));
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: StatusBadge(status: bleState.status),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!isConnected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: AppColors.warning.withValues(alpha: 0.15),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: AppColors.warning, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Radio Node offline. Outbound messages will be queued in SQLite.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Messages Area
            Expanded(
              child: messagesAsync.when(
                data: (messages) {
                  if (messages.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages in this thread yet.\nType below to transmit via LoRa.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                      ),
                    );
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      return _buildMessageBubble(msg);
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
                error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.error))),
              ),
            ),

            // Message Composer Area
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel msg) {
    final isMe = !msg.isIncoming;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.surfaceHighlight : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(color: isMe ? AppColors.accent.withValues(alpha: 0.2) : AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.textContent,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.createdAt),
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
                if (msg.isEncrypted) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.lock, size: 10, color: AppColors.connected),
                ],
                if (!isMe && msg.rssi != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${msg.rssi} dBm',
                    style: const TextStyle(fontSize: 10, color: AppColors.accent),
                  ),
                ],
                if (isMe) ...[
                  const SizedBox(width: 6),
                  _buildDeliveryStatusIcon(msg),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryStatusIcon(MessageModel msg) {
    switch (msg.deliveryStatus) {
      case MessageDeliveryStatus.queued:
        return const Icon(Icons.schedule, size: 14, color: AppColors.textMuted);
      case MessageDeliveryStatus.transmitted:
        return const Icon(Icons.done, size: 14, color: AppColors.textSecondary);
      case MessageDeliveryStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: AppColors.connected);
      case MessageDeliveryStatus.failed:
        return InkWell(
          onTap: () => ref.read(chatRepositoryProvider).retryMessage(msg.id),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: AppColors.error),
              SizedBox(width: 3),
              Text('Retry', style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      case MessageDeliveryStatus.draft:
        return const SizedBox.shrink();
    }
  }

  Widget _buildComposer() {
    final currentLen = _textController.text.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  maxLength: _maxChars,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Transmit message via LoRa...',
                    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                  onPressed: _isComposing ? _sendMessage : null,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$currentLen / $_maxChars B',
                style: TextStyle(
                  fontSize: 11,
                  color: currentLen > 160 ? AppColors.warning : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int timestampSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}
