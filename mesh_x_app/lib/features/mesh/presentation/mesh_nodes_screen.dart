import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../chat/presentation/chat_conversation_screen.dart';
import '../../device/presentation/ble_controller.dart';
import '../domain/mesh_node_model.dart';
import 'key_exchange_dialog.dart';
import 'widgets/mesh_topology_graph.dart';
import 'widgets/tactical_radar_map.dart';

class MeshNodesScreen extends ConsumerStatefulWidget {
  const MeshNodesScreen({super.key});

  @override
  ConsumerState<MeshNodesScreen> createState() => _MeshNodesScreenState();
}

class _MeshNodesScreenState extends ConsumerState<MeshNodesScreen> {
  int _viewMode = 0; // 0: List, 1: Topology Graph, 2: Tactical Radar

  @override
  Widget build(BuildContext context) {
    final nodesAsync = ref.watch(discoveredNodesProvider);
    final bleState = ref.watch(bleControllerProvider);
    final localNodeId = bleState.deviceInfo?.nodeId ?? 0;

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
      body: Column(
        children: [
          // View Mode Selector Tabs
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _buildViewTab(0, Icons.view_list_rounded, 'Node List'),
                _buildViewTab(1, Icons.hub_rounded, 'Visual Graph'),
                _buildViewTab(2, Icons.radar_rounded, 'Tactical Radar'),
              ],
            ),
          ),

          // Main View Content
          Expanded(
            child: _buildMainContent(nodesAsync, localNodeId, bleState),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(
    AsyncValue<List<MeshNodeModel>> nodesAsync,
    int localNodeId,
    dynamic bleState,
  ) {
    final nodes = nodesAsync.value ?? const [];

    if (_viewMode == 1) {
      return MeshTopologyGraph(
        nodes: nodes,
        localNodeId: localNodeId,
      );
    } else if (_viewMode == 2) {
      return TacticalRadarMap(
        nodes: nodes,
        localNodeId: localNodeId,
      );
    }

    return _buildListView(nodes, bleState, isLoading: nodesAsync.isLoading);
  }

  Widget _buildViewTab(int index, IconData icon, String label) {
    final isSelected = _viewMode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_viewMode != index) {
            HapticFeedback.selectionClick();
            setState(() => _viewMode = index);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceHighlight : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isSelected ? Border.all(color: AppColors.border) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? AppColors.accent : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListView(List<MeshNodeModel> nodes, dynamic bleState, {bool isLoading = false}) {
    final directCount = nodes.where((n) => n.isDirectNeighbor).length;
    final relayedCount = nodes.length - directCount;

    return Column(
      children: [
        // Summary Metric Cards
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
          child: (isLoading && nodes.isEmpty)
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                )
              : nodes.isEmpty
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

