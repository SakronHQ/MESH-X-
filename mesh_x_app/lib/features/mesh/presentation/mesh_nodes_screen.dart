import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../chat/presentation/chat_conversation_screen.dart';
import '../../device/presentation/ble_controller.dart';
import '../domain/mesh_node_model.dart';
import 'key_exchange_dialog.dart';

class MeshNodesScreen extends ConsumerWidget {
  const MeshNodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodesAsync = ref.watch(discoveredNodesProvider);
    final bleState = ref.watch(bleControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mesh Topology'),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(Icons.qr_code_rounded, color: AppColors.accent, size: 18),
            ),
            tooltip: 'My Identity & Keys',
            onPressed: () {
              HapticFeedback.lightImpact();
              showDialog(
                context: context,
                builder: (_) => const KeyExchangeDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh Nodes',
            onPressed: () {
              HapticFeedback.selectionClick();
              ref.invalidate(discoveredNodesProvider);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: nodesAsync.when(
        data: (nodes) {
          final directCount = nodes.where((n) => n.isDirectNeighbor).length;
          final relayedCount = nodes.length - directCount;

          return Column(
            children: [
              // Summary Metric Cards
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Discovered',
                        value: '${nodes.length}',
                        icon: Icons.hub_rounded,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Direct (1 Hop)',
                        value: '$directCount',
                        icon: Icons.near_me_rounded,
                        color: AppColors.connected,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Relayed (>1 Hop)',
                        value: '$relayedCount',
                        icon: Icons.alt_route_rounded,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),

              // Status Banner
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      bleState.isConnected
                          ? Icons.sensors_rounded
                          : Icons.sensors_off_rounded,
                      size: 18,
                      color: bleState.isConnected
                          ? AppColors.connected
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bleState.isConnected
                            ? 'Mesh Radio Active: Autonomous multi-hop forwarding & deduplication enabled.'
                            : 'Hardware Node Disconnected: Connect via BLE to discover mesh peers.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Discovered Nodes List
              Expanded(
                child: nodes.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                        itemCount: nodes.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final node = nodes[index];
                          return _buildNodeCard(context, ref, node);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (err, _) => Center(
          child: Text(
            'Error loading mesh nodes: $err',
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.hub_outlined,
                size: 30,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Mesh Peers Discovered',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'When nearby ESP32 nodes broadcast presence across the 433 MHz LoRa band, they will appear here automatically with hop counts and RF metrics.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, WidgetRef ref, MeshNodeModel node) {
    final signalColor = node.lastRssi > -90
        ? AppColors.connected
        : (node.lastRssi > -110 ? AppColors.warning : AppColors.error);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Node Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: node.isDirectNeighbor
                  ? AppColors.accent.withValues(alpha: 0.12)
                  : AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: node.isDirectNeighbor
                    ? AppColors.accent.withValues(alpha: 0.3)
                    : AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              node.isDirectNeighbor ? Icons.router_rounded : Icons.alt_route_rounded,
              color: node.isDirectNeighbor ? AppColors.accent : AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      node.formattedNodeHex,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: node.isDirectNeighbor
                            ? AppColors.connected.withValues(alpha: 0.18)
                            : AppColors.warning.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        node.isDirectNeighbor ? '1 HOP DIRECT' : '${node.hopDistance} HOPS RELAY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: node.isDirectNeighbor
                              ? AppColors.connected
                              : AppColors.warning,
                        ),
                      ),
                    ),
                    if (node.hasPublicKey) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.connected.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock, size: 9, color: AppColors.connected),
                            SizedBox(width: 3),
                            Text(
                              'E2EE',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: AppColors.connected,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.signal_cellular_alt_rounded, size: 13, color: signalColor),
                    const SizedBox(width: 4),
                    Text(
                      '${node.lastRssi} dBm',
                      style: TextStyle(
                        fontSize: 11,
                        color: signalColor,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SNR: ${node.lastSnr.toStringAsFixed(1)} dB',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${node.relativeLastSeen}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Key Pairing Button
          IconButton(
            icon: Icon(
              node.hasPublicKey ? Icons.shield_rounded : Icons.key_rounded,
              size: 20,
              color: node.hasPublicKey ? AppColors.connected : AppColors.textMuted,
            ),
            tooltip: node.hasPublicKey ? 'Key Verified (E2EE Active)' : 'Pair E2EE Key',
            onPressed: () {
              HapticFeedback.lightImpact();
              showDialog(
                context: context,
                builder: (_) => KeyExchangeDialog(peerNodeId: node.nodeId),
              );
            },
          ),
          const SizedBox(width: 4),

          // Chat Button
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceHighlight,
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(44, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              HapticFeedback.selectionClick();
              final chatRepo = ref.read(chatRepositoryProvider);
              final conv = await chatRepo.ensureConversationForNode(node.nodeId);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ChatConversationScreen(
                      conversation: conv,
                    ),
                  ),
                );
              }
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 15),
                SizedBox(width: 5),
                Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

