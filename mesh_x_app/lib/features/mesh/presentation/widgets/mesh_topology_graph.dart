import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chat/domain/conversation_model.dart';
import '../../../chat/presentation/chat_conversation_screen.dart';
import '../../domain/mesh_node_model.dart';
import '../key_exchange_dialog.dart';

class MeshTopologyGraph extends StatefulWidget {
  final List<MeshNodeModel> nodes;
  final int localNodeId;

  const MeshTopologyGraph({
    super.key,
    required this.nodes,
    required this.localNodeId,
  });

  @override
  State<MeshTopologyGraph> createState() => _MeshTopologyGraphState();
}

class _MeshTopologyGraphState extends State<MeshTopologyGraph>
    with SingleTickerProviderStateMixin {
  int? _selectedNodeId;
  late AnimationController _pulseController;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.hub_outlined, size: 36, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Discovered Nodes on Graph',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Waiting for RF presence beacons from nearby LoRa mesh nodes...',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        final nodePositions = _computeNodePositions(center, constraints);

        final selectedNode = _selectedNodeId != null
            ? widget.nodes.where((n) => n.nodeId == _selectedNodeId).firstOrNull
            : null;

        return Stack(
          children: [
            // Interactive Canvas (Pan and Zoom)
            InteractiveViewer(
              transformationController: _transformController,
              boundaryMargin: const EdgeInsets.all(120),
              minScale: 0.6,
              maxScale: 2.5,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return GestureDetector(
                    onTapUp: (details) {
                      final tapPos = details.localPosition;
                      MeshNodeModel? hitNode;
                      for (final entry in nodePositions.entries) {
                        if ((entry.value - tapPos).distance <= 30.0) {
                          hitNode = entry.key;
                          break;
                        }
                      }
                      setState(() {
                        _selectedNodeId = hitNode?.nodeId;
                      });
                      if (hitNode != null) {
                        HapticFeedback.selectionClick();
                      }
                    },
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: _TopologyPainter(
                        nodes: widget.nodes,
                        nodePositions: nodePositions,
                        center: center,
                        localNodeId: widget.localNodeId,
                        selectedNode: selectedNode,
                        pulseValue: _pulseController.value,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Top Status Bar
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceGlass,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderGlass),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.circle, size: 8, color: AppColors.connected),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.nodes.length} Nodes Active',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.center_focus_strong_rounded, size: 18),
                    tooltip: 'Recenter Graph',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _transformController.value = Matrix4.identity();
                    },
                  ),
                ],
              ),
            ),

            // Bottom Selected Node Inspector Card
            if (selectedNode != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildNodeDetailCard(selectedNode),
              ),
          ],
        );
      },
    );
  }

  Map<MeshNodeModel, Offset> _computeNodePositions(Offset center, BoxConstraints constraints) {
    final positions = <MeshNodeModel, Offset>{};
    final direct = widget.nodes.where((n) => n.isDirectNeighbor).toList();
    final relayed = widget.nodes.where((n) => !n.isDirectNeighbor).toList();

    final maxRadius = min(constraints.maxWidth, constraints.maxHeight) * 0.44;
    final r1 = maxRadius * 0.52;
    final r2 = maxRadius * 0.90;

    // Distribute Hop-1 nodes along inner circle
    for (int i = 0; i < direct.length; i++) {
      final angle = (2 * pi * i / direct.length) - (pi / 2);
      positions[direct[i]] = Offset(
        center.dx + r1 * cos(angle),
        center.dy + r1 * sin(angle),
      );
    }

    // Distribute Hop > 1 nodes along outer circle
    for (int i = 0; i < relayed.length; i++) {
      final angle = (2 * pi * i / max(1, relayed.length)) - (pi / 4);
      positions[relayed[i]] = Offset(
        center.dx + r2 * cos(angle),
        center.dy + r2 * sin(angle),
      );
    }

    return positions;
  }

  Widget _buildNodeDetailCard(MeshNodeModel node) {
    final isDirect = node.isDirectNeighbor;
    final signalColor = node.lastRssi > -90
        ? AppColors.connected
        : (node.lastRssi > -110 ? AppColors.warning : AppColors.error);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDirect
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: signalColor),
                ),
                child: Icon(
                  isDirect ? Icons.router_rounded : Icons.alt_route_rounded,
                  size: 20,
                  color: signalColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.alias,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${node.formattedNodeHex} • ${node.hopDistance} ${node.hopDistance == 1 ? "Hop (Direct)" : "Hops (Relayed)"}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                onPressed: () => setState(() => _selectedNodeId = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildBadge('RSSI', '${node.lastRssi} dBm', signalColor),
              const SizedBox(width: 8),
              _buildBadge('SNR', '${node.lastSnr.toStringAsFixed(1)} dB', AppColors.accent),
              const SizedBox(width: 8),
              _buildBadge(
                'E2EE',
                node.isVerified ? 'VERIFIED' : (node.hasPublicKey ? 'AVAILABLE' : 'NONE'),
                node.isVerified ? AppColors.connected : AppColors.textMuted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.key_rounded, size: 14),
                  label: const Text('E2EE Keys', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => KeyExchangeDialog(peerNodeId: node.nodeId),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.background,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                  label: const Text('Start Chat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  onPressed: () {
                    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                    final conv = ConversationModel(
                      id: node.formattedNodeHex,
                      title: node.alias,
                      peerNodeId: node.nodeId,
                      createdAt: now,
                      updatedAt: now,
                    );
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatConversationScreen(
                          conversation: conv,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopologyPainter extends CustomPainter {
  final List<MeshNodeModel> nodes;
  final Map<MeshNodeModel, Offset> nodePositions;
  final Offset center;
  final int localNodeId;
  final MeshNodeModel? selectedNode;
  final double pulseValue;

  _TopologyPainter({
    required this.nodes,
    required this.nodePositions,
    required this.center,
    required this.localNodeId,
    required this.selectedNode,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final maxRadius = min(size.width, size.height) * 0.44;
    final r1 = maxRadius * 0.52;
    final r2 = maxRadius * 0.90;

    // 1. Draw Range Rings (Concentric hop circles)
    final ringPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, r1, ringPaint);
    canvas.drawCircle(center, r2, ringPaint);

    // Hop labels
    _drawText(canvas, '1-HOP DIRECT', Offset(center.dx + 4, center.dy - r1 + 4), AppColors.textMuted, 8);
    _drawText(canvas, 'MULTI-HOP RELAY', Offset(center.dx + 4, center.dy - r2 + 4), AppColors.textMuted, 8);

    // 2. Draw Gateway Central Pulse
    final pulsePaint = Paint()
      ..color = AppColors.accent.withValues(alpha: (1.0 - pulseValue) * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + (pulseValue * 12.0);
    canvas.drawCircle(center, 22.0 + (pulseValue * 14.0), pulsePaint);

    // 3. Draw Links between nodes
    final linkPaint = Paint()..strokeWidth = 1.5;

    for (final node in nodes) {
      final pos = nodePositions[node];
      if (pos == null) continue;

      if (node.isDirectNeighbor) {
        // Link to local gateway
        linkPaint.color = node.lastRssi > -90
            ? AppColors.connected.withValues(alpha: 0.6)
            : (node.lastRssi > -110
                ? AppColors.warning.withValues(alpha: 0.5)
                : AppColors.error.withValues(alpha: 0.4));
        canvas.drawLine(center, pos, linkPaint);
      } else {
        // Relayed link from nearest Hop-1 node
        final nearest = _findNearestHop1Node(pos);
        if (nearest != null) {
          linkPaint.color = AppColors.warning.withValues(alpha: 0.4);
          canvas.drawLine(nearest, pos, linkPaint);
        } else {
          linkPaint.color = AppColors.border.withValues(alpha: 0.4);
          canvas.drawLine(center, pos, linkPaint);
        }
      }
    }

    // 4. Draw Peripheral Discovered Nodes
    for (final entry in nodePositions.entries) {
      final node = entry.key;
      final pos = entry.value;
      final isSelected = selectedNode?.nodeId == node.nodeId;

      final statusColor = node.lastRssi > -90
          ? AppColors.connected
          : (node.lastRssi > -110 ? AppColors.warning : AppColors.error);

      // Selection ring
      if (isSelected) {
        final selPaint = Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(pos, 22, selPaint);
      }

      // Outer glow
      final glowPaint = Paint()
        ..color = statusColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 18, glowPaint);

      // Node Body
      final bodyPaint = Paint()
        ..color = AppColors.surfaceElevated
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 14, bodyPaint);

      final borderPaint = Paint()
        ..color = statusColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(pos, 14, borderPaint);

      // Lock badge if verified
      if (node.isVerified) {
        final lockPaint = Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(pos.dx + 10, pos.dy - 10), 5, lockPaint);
      }

      // Node Alias Label
      _drawText(
        canvas,
        node.alias,
        Offset(pos.dx, pos.dy + 18),
        isSelected ? AppColors.accent : AppColors.textPrimary,
        10,
        alignCenter: true,
      );

      // RSSI Label
      _drawText(
        canvas,
        '${node.lastRssi} dBm',
        Offset(pos.dx, pos.dy + 30),
        statusColor,
        9,
        alignCenter: true,
      );
    }

    // 5. Draw Local Gateway Center Node
    final centerGlow = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 24, centerGlow);

    final centerBody = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 18, centerBody);

    final centerBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 18, centerBorder);

    _drawText(
      canvas,
      'GATEWAY',
      Offset(center.dx, center.dy + 22),
      AppColors.accent,
      9,
      alignCenter: true,
      bold: true,
    );
  }

  Offset? _findNearestHop1Node(Offset pos) {
    Offset? best;
    double bestDist = double.infinity;
    for (final entry in nodePositions.entries) {
      if (entry.key.isDirectNeighbor) {
        final d = (entry.value - pos).distance;
        if (d < bestDist) {
          bestDist = d;
          best = entry.value;
        }
      }
    }
    return best;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize, {
    bool alignCenter = false,
    bool bold = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final drawOffset = alignCenter
        ? Offset(offset.dx - tp.width / 2, offset.dy)
        : offset;
    tp.paint(canvas, drawOffset);
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.selectedNode != selectedNode ||
        oldDelegate.pulseValue != pulseValue;
  }
}
