import 'package:flutter/material.dart';
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
        title: const Text('Mesh Topology & Nodes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code, color: AppColors.accent),
            tooltip: 'My Identity & Keys',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const KeyExchangeDialog(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Nodes',
            onPressed: () => ref.invalidate(discoveredNodesProvider),
          ),
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Total Discovered',
                        value: '${nodes.length}',
                        icon: Icons.hub_outlined,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Direct (1 Hop)',
                        value: '$directCount',
                        icon: Icons.near_me_outlined,
                        color: AppColors.connected,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildMetricCard(
                        title: 'Relayed (>1 Hop)',
                        value: '$relayedCount',
                        icon: Icons.alt_route_outlined,
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
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      bleState.isConnected ? Icons.sensors : Icons.sensors_off,
                      size: 18,
                      color: bleState.isConnected ? AppColors.connected : AppColors.textMuted,
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          child: Text('Error loading mesh nodes: $err',
              style: const TextStyle(color: AppColors.error)),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
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
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hub_outlined,
                size: 48,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Mesh Peers Discovered Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'When nearby ESP32 nodes broadcast presence or relay messages across the 433 MHz LoRa band, they will appear here automatically with hop distances and RF metrics.',
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Node Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: node.isDirectNeighbor
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: node.isDirectNeighbor
                    ? AppColors.accent.withValues(alpha: 0.3)
                    : AppColors.warning.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              node.isDirectNeighbor ? Icons.router : Icons.alt_route,
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
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: node.isDirectNeighbor
                            ? AppColors.connected.withValues(alpha: 0.2)
                            : AppColors.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        node.isDirectNeighbor ? '1 HOP DIRECT' : '${node.hopDistance} HOPS RELAY',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
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
                          color: AppColors.connected.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
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
                    Icon(Icons.signal_cellular_alt, size: 13, color: signalColor),
                    const SizedBox(width: 4),
                    Text(
                      '${node.lastRssi} dBm',
                      style: TextStyle(
                        fontSize: 12,
                        color: signalColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'SNR: ${node.lastSnr.toStringAsFixed(1)} dB',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '• ${node.relativeLastSeen}',
                      style: const TextStyle(
                        fontSize: 12,
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
              node.hasPublicKey ? Icons.shield : Icons.key_outlined,
              size: 18,
              color: node.hasPublicKey ? AppColors.connected : AppColors.textMuted,
            ),
            tooltip: node.hasPublicKey ? 'Key Verified (E2EE Active)' : 'Pair E2EE Key',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => KeyExchangeDialog(peerNodeId: node.nodeId),
              );
            },
          ),
          const SizedBox(width: 6),

          // Chat Button
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceHighlight,
              foregroundColor: AppColors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(44, 38),
            ),
            onPressed: () async {
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
                Icon(Icons.chat_bubble_outline, size: 16),
                SizedBox(width: 4),
                Text('Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
