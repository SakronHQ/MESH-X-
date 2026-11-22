import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/geo_utils.dart';
import '../../../chat/domain/conversation_model.dart';
import '../../../chat/presentation/chat_conversation_screen.dart';
import '../../../sos/domain/sos_alert_model.dart';
import '../../../sos/presentation/sos_composer_dialog.dart';
import '../../../sos/presentation/sos_controller.dart';
import '../../domain/mesh_node_model.dart';

class TacticalRadarMap extends ConsumerStatefulWidget {
  final List<MeshNodeModel> nodes;
  final int localNodeId;

  const TacticalRadarMap({
    super.key,
    required this.nodes,
    required this.localNodeId,
  });

  @override
  ConsumerState<TacticalRadarMap> createState() => _TacticalRadarMapState();
}

class _TacticalRadarMapState extends ConsumerState<TacticalRadarMap>
    with SingleTickerProviderStateMixin {
  Position? _myPosition;
  bool _isAcquiringGps = false;
  double _radarMaxRangeMeters = 2000.0; // 2 km default range
  late AnimationController _sweepController;

  dynamic _selectedTarget; // MeshNodeModel or SosAlertModel

  final List<double> _rangePresets = [500.0, 1000.0, 2000.0, 5000.0, 10000.0];

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();
    _fetchGpsLocation();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  Future<void> _fetchGpsLocation() async {
    if (!mounted) return;
    setState(() => _isAcquiringGps = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _isAcquiringGps = false);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          if (mounted) setState(() => _isAcquiringGps = false);
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _isAcquiringGps = false);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      if (mounted) {
        setState(() {
          _myPosition = pos;
          _isAcquiringGps = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isAcquiringGps = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sosAlerts = ref.watch(sosHistoryProvider);
    final activeSos = ref.watch(activeSosAlertProvider);

    // Merge active SOS if not in history
    final allAlerts = [...sosAlerts];
    if (activeSos != null && !allAlerts.any((a) => a.packetId == activeSos.packetId)) {
      allAlerts.insert(0, activeSos);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        final radarRadius = min(constraints.maxWidth, constraints.maxHeight) * 0.44;

        // Compute targets positions
        final mappedTargets = _computeTargetPositions(
          center: center,
          radarRadius: radarRadius,
          maxRange: _radarMaxRangeMeters,
          alerts: allAlerts,
        );

        return Stack(
          children: [
            // Radar Custom Paint Canvas
            AnimatedBuilder(
              animation: _sweepController,
              builder: (context, child) {
                return GestureDetector(
                  onTapUp: (details) {
                    final tap = details.localPosition;
                    dynamic hit;
                    for (final item in mappedTargets) {
                      if ((item.screenOffset - tap).distance <= 28.0) {
                        hit = item.target;
                        break;
                      }
                    }
                    setState(() => _selectedTarget = hit);
                    if (hit != null) {
                      HapticFeedback.selectionClick();
                    }
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                    painter: _RadarPainter(
                      center: center,
                      radius: radarRadius,
                      maxRangeMeters: _radarMaxRangeMeters,
                      sweepAngle: _sweepController.value * 2 * pi,
                      mappedTargets: mappedTargets,
                      selectedTarget: _selectedTarget,
                      hasGpsFix: _myPosition != null,
                    ),
                  ),
                );
              },
            ),

            // Top HUD Overlay
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
                        Icon(
                          _myPosition != null ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                          size: 14,
                          color: _myPosition != null ? AppColors.connected : AppColors.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _myPosition != null
                              ? '${_myPosition!.latitude.toStringAsFixed(4)}°, ${_myPosition!.longitude.toStringAsFixed(4)}°'
                              : (_isAcquiringGps ? 'Acquiring GPS...' : 'Simulated GPS Datum'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'monospace',
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Refresh GPS button
                  IconButton.filledTonal(
                    icon: _isAcquiringGps
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 16),
                    tooltip: 'Update Location',
                    onPressed: _fetchGpsLocation,
                  ),
                ],
              ),
            ),

            // Range Preset Selector
            Positioned(
              top: 56,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceGlass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderGlass),
                ),
                child: Column(
                  children: _rangePresets.map((r) {
                    final isSel = (_radarMaxRangeMeters - r).abs() < 1.0;
                    return InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _radarMaxRangeMeters = r);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSel ? AppColors.accent.withValues(alpha: 0.25) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          GeoUtils.formatDistance(r),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                            color: isSel ? AppColors.accent : AppColors.textMuted,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Emergency SOS Composer Floating Button
            Positioned(
              bottom: _selectedTarget != null ? 150 : 20,
              right: 16,
              child: FloatingActionButton.extended(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 4,
                icon: const Icon(Icons.sos_rounded, size: 20),
                label: const Text(
                  'BROADCAST SOS',
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
                onPressed: () {
                  HapticFeedback.heavyImpact();
                  showDialog(
                    context: context,
                    builder: (_) => const SosComposerDialog(),
                  );
                },
              ),
            ),

            // Selected Target Card
            if (_selectedTarget != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildTargetInspector(_selectedTarget!),
              ),
          ],
        );
      },
    );
  }

  List<_MappedRadarTarget> _computeTargetPositions({
    required Offset center,
    required double radarRadius,
    required double maxRange,
    required List<SosAlertModel> alerts,
  }) {
    final list = <_MappedRadarTarget>[];

    // Reference datum
    final myLat = _myPosition?.latitude ?? 23.8103; // Default fallback datum
    final myLon = _myPosition?.longitude ?? 90.4125;

    // 1. Process SOS Alerts with GPS
    for (final alert in alerts) {
      if (alert.hasLocation) {
        final dist = GeoUtils.computeDistanceMeters(
          myLat,
          myLon,
          alert.latitude!,
          alert.longitude!,
        );
        final bearing = GeoUtils.computeBearingDegrees(
          myLat,
          myLon,
          alert.latitude!,
          alert.longitude!,
        );

        final clampedDist = min(dist, maxRange);
        final screenDist = (clampedDist / maxRange) * radarRadius;
        final rad = (bearing - 90) * (pi / 180.0);
        final pos = Offset(center.dx + screenDist * cos(rad), center.dy + screenDist * sin(rad));

        list.add(_MappedRadarTarget(
          target: alert,
          screenOffset: pos,
          distanceMeters: dist,
          bearingDegrees: bearing,
          isSos: true,
        ));
      }
    }

    // 2. Process Discovered Mesh Nodes
    for (int i = 0; i < widget.nodes.length; i++) {
      final node = widget.nodes[i];
      // Check if node is already shown via an SOS alert
      final hasSos = alerts.any((a) => a.senderNodeId == node.nodeId);
      if (hasSos) continue;

      // Estimate distance from RSSI
      final estDist = GeoUtils.estimateDistanceMetersFromRssi(node.lastRssi);
      // Deterministic bearing based on Node ID hash
      final angleDeg = ((node.nodeId.abs() * 37) % 360).toDouble();

      final clampedDist = min(estDist, maxRange);
      final screenDist = (clampedDist / maxRange) * radarRadius;
      final rad = (angleDeg - 90) * (pi / 180.0);
      final pos = Offset(center.dx + screenDist * cos(rad), center.dy + screenDist * sin(rad));

      list.add(_MappedRadarTarget(
        target: node,
        screenOffset: pos,
        distanceMeters: estDist,
        bearingDegrees: angleDeg,
        isSos: false,
      ));
    }

    return list;
  }

  Widget _buildTargetInspector(dynamic target) {
    if (target is SosAlertModel) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.error, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
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
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCY SOS: ${target.formattedNodeHex}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                        ),
                      ),
                      Text(
                        target.distressMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() => _selectedTarget = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Coordinates: ${target.locationString}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy GPS', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: target.locationString));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Coordinates copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
                    label: const Text('Reply to Node', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    onPressed: () {
                      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                      final conv = ConversationModel(
                        id: target.formattedNodeHex,
                        title: 'Emergency Node ${target.formattedNodeHex}',
                        peerNodeId: target.senderNodeId,
                        createdAt: now,
                        updatedAt: now,
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatConversationScreen(conversation: conv),
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
    } else if (target is MeshNodeModel) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
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
                const Icon(Icons.router_rounded, color: AppColors.accent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${target.alias} (${target.formattedNodeHex})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  onPressed: () => setState(() => _selectedTarget = null),
                ),
              ],
            ),
            Text(
              'Est. Distance: ~${GeoUtils.formatDistance(GeoUtils.estimateDistanceMetersFromRssi(target.lastRssi))} (RSSI: ${target.lastRssi} dBm)',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                minimumSize: const Size(double.infinity, 38),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 14),
              label: const Text('Open Direct Chat Channel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              onPressed: () {
                final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                final conv = ConversationModel(
                  id: target.formattedNodeHex,
                  title: target.alias,
                  peerNodeId: target.nodeId,
                  createdAt: now,
                  updatedAt: now,
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatConversationScreen(conversation: conv),
                  ),
                );
              },
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _MappedRadarTarget {
  final dynamic target;
  final Offset screenOffset;
  final double distanceMeters;
  final double bearingDegrees;
  final bool isSos;

  _MappedRadarTarget({
    required this.target,
    required this.screenOffset,
    required this.distanceMeters,
    required this.bearingDegrees,
    required this.isSos,
  });
}

class _RadarPainter extends CustomPainter {
  final Offset center;
  final double radius;
  final double maxRangeMeters;
  final double sweepAngle;
  final List<_MappedRadarTarget> mappedTargets;
  final dynamic selectedTarget;
  final bool hasGpsFix;

  _RadarPainter({
    required this.center,
    required this.radius,
    required this.maxRangeMeters,
    required this.sweepAngle,
    required this.mappedTargets,
    required this.selectedTarget,
    required this.hasGpsFix,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Concentric Range Rings (4 rings)
    final ringPaint = Paint()
      ..color = const Color(0xFF00FF66).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      final r = radius * (i / 4.0);
      canvas.drawCircle(center, r, ringPaint);
      final rangeText = GeoUtils.formatDistance(maxRangeMeters * (i / 4.0));
      _drawText(canvas, rangeText, Offset(center.dx + 4, center.dy - r + 3), const Color(0xFF00FF66).withValues(alpha: 0.4), 8);
    }

    // 2. Crosshairs & Radial Guide Lines
    final crossPaint = Paint()
      ..color = const Color(0xFF00FF66).withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), crossPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), crossPaint);

    // Cardinal Points
    _drawText(canvas, 'N', Offset(center.dx, center.dy - radius - 16), AppColors.accent, 12, alignCenter: true, bold: true);
    _drawText(canvas, 'S', Offset(center.dx, center.dy + radius + 4), AppColors.textMuted, 10, alignCenter: true);
    _drawText(canvas, 'E', Offset(center.dx + radius + 6, center.dy - 6), AppColors.textMuted, 10);
    _drawText(canvas, 'W', Offset(center.dx - radius - 18, center.dy - 6), AppColors.textMuted, 10);

    // 3. Rotating Sweep Beam
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0.0,
        endAngle: 2 * pi,
        colors: [
          Colors.transparent,
          const Color(0xFF00FF66).withValues(alpha: 0.22),
          Colors.transparent,
        ],
        stops: const [0.0, 0.95, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);

    // 4. Plot Targets
    for (final item in mappedTargets) {
      final pos = item.screenOffset;
      final isSel = selectedTarget == item.target;

      if (item.isSos) {
        // Red Emergency Beacon
        final sosBeaconPaint = Paint()
          ..color = AppColors.error
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, 8, sosBeaconPaint);

        final sosRingPaint = Paint()
          ..color = AppColors.error.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(pos, 16, sosRingPaint);

        _drawText(canvas, 'SOS!', Offset(pos.dx, pos.dy + 12), AppColors.error, 10, alignCenter: true, bold: true);
      } else {
        // Normal Node Blip
        final blipPaint = Paint()
          ..color = const Color(0xFF00FF66)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, 6, blipPaint);

        if (item.target is MeshNodeModel) {
          final node = item.target as MeshNodeModel;
          _drawText(canvas, node.alias, Offset(pos.dx, pos.dy + 8), AppColors.textSecondary, 8, alignCenter: true);
        }
      }

      // Selection Halo
      if (isSel) {
        final selHalo = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(pos, 20, selHalo);
      }
    }

    // 5. Center Self Reticle
    final centerReticle = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, centerReticle);

    final centerCross = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(center.dx - 10, center.dy), Offset(center.dx + 10, center.dy), centerCross);
    canvas.drawLine(Offset(center.dx, center.dy - 10), Offset(center.dx, center.dy + 10), centerCross);
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
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.maxRangeMeters != maxRangeMeters ||
        oldDelegate.selectedTarget != selectedTarget ||
        oldDelegate.mappedTargets.length != mappedTargets.length;
  }
}
