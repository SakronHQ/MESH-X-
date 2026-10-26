import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../device/presentation/ble_controller.dart';

class SosComposerDialog extends ConsumerStatefulWidget {
  const SosComposerDialog({super.key});

  @override
  ConsumerState<SosComposerDialog> createState() => _SosComposerDialogState();
}

class _SosComposerDialogState extends ConsumerState<SosComposerDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _customNotesController = TextEditingController();

  String _selectedCategory = '🚑 Medical Emergency';
  final List<String> _categories = [
    '🚑 Medical Emergency',
    '🧭 Lost / Evacuation',
    '🔥 Fire / Hazard',
    '⚠️ Search & Rescue',
    '🆘 General Distress',
  ];

  bool _includeGps = true;
  bool _isAcquiringGps = false;
  Position? _currentPosition;
  String? _gpsError;

  late AnimationController _holdController;
  bool _isHolding = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _triggerEmergencyBroadcast();
      }
    });

    _acquireLocation();
  }

  @override
  void dispose() {
    _holdController.dispose();
    _customNotesController.dispose();
    super.dispose();
  }

  Future<void> _acquireLocation() async {
    setState(() {
      _isAcquiringGps = true;
      _gpsError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsError = 'Location services disabled on device.';
          _isAcquiringGps = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsError = 'Location permission denied.';
            _isAcquiringGps = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsError = 'Location permission permanently denied.';
          _isAcquiringGps = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      setState(() {
        _currentPosition = position;
        _isAcquiringGps = false;
      });
    } catch (e) {
      setState(() {
        _gpsError = 'Failed to acquire GPS: $e';
        _isAcquiringGps = false;
      });
    }
  }

  void _onHoldStart() {
    if (_isSending) return;
    HapticFeedback.heavyImpact();
    setState(() => _isHolding = true);
    _holdController.forward(from: 0.0);
  }

  void _onHoldEnd() {
    if (_holdController.status != AnimationStatus.completed) {
      _holdController.reset();
      setState(() => _isHolding = false);
    }
  }

  Future<void> _triggerEmergencyBroadcast() async {
    HapticFeedback.vibrate();
    setState(() {
      _isSending = true;
      _isHolding = false;
    });

    final bleState = ref.read(bleControllerProvider);
    final localNodeId = bleState.deviceInfo?.nodeId ?? 0x11111111;
    final chatRepo = ref.read(chatRepositoryProvider);

    final notes = _customNotesController.text.trim();
    final distressMessage = notes.isNotEmpty
        ? '$_selectedCategory - $notes'
        : _selectedCategory;

    final lat = (_includeGps && _currentPosition != null)
        ? _currentPosition!.latitude
        : null;
    final lon = (_includeGps && _currentPosition != null)
        ? _currentPosition!.longitude
        : null;

    try {
      await chatRepo.submitSos(
        distressMessage: distressMessage,
        latitude: lat,
        longitude: lon,
        localNodeId: localNodeId,
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.error,
            content: Text(
              '🚨 High-priority SOS distress broadcast transmitted over mesh!',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to transmit SOS: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF160A0C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.error.withValues(alpha: 0.6), width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.emergency_rounded,
                    color: AppColors.error,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMERGENCY SOS',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        'Flood broadcast to all mesh nodes',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(color: Color(0xFF331414), height: 1),
            const SizedBox(height: 16),

            // Emergency Category
            const Text(
              'Select Emergency Type',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF200D0D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF451919)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF200D0D),
                  icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.error),
                  items: _categories.map((cat) {
                    return DropdownMenuItem(
                      value: cat,
                      child: Text(
                        cat,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Optional Details
            const Text(
              'Additional Distress Details (Optional)',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _customNotesController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g. 2 people injured, steep ravine near milestone 4',
                hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.6), fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF200D0D),
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF451919)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF451919)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.error),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // GPS Telemetry Switch
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF200D0D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF451919)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Attach GPS Coordinates',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _includeGps,
                        activeThumbColor: AppColors.accent,
                        onChanged: (val) => setState(() => _includeGps = val),
                      ),
                    ],
                  ),
                  if (_includeGps) ...[
                    const Divider(color: Color(0xFF331414), height: 12),
                    Row(
                      children: [
                        if (_isAcquiringGps) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Acquiring satellite fix...',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ] else if (_currentPosition != null) ...[
                          const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Fix: ${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)} (±${_currentPosition!.accuracy.round()}m)',
                              style: const TextStyle(color: AppColors.accent, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else ...[
                          const Icon(Icons.warning_amber, color: AppColors.warning, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _gpsError ?? 'No GPS fix acquired.',
                              style: const TextStyle(color: AppColors.warning, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
                          onPressed: _isAcquiringGps ? null : _acquireLocation,
                          tooltip: 'Retry GPS Fix',
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Hold-to-Send 3s Safety Trigger
            Center(
              child: Column(
                children: [
                  Text(
                    _isSending
                        ? 'Broadcasting SOS distress packet...'
                        : (_isHolding
                            ? 'KEEP HOLDING FOR 3 SECONDS...'
                            : 'PRESS AND HOLD 3 SECONDS TO BROADCAST'),
                    style: TextStyle(
                      color: _isHolding ? AppColors.error : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTapDown: (_) => _onHoldStart(),
                    onTapUp: (_) => _onHoldEnd(),
                    onTapCancel: () => _onHoldEnd(),
                    child: AnimatedBuilder(
                      animation: _holdController,
                      builder: (context, child) {
                        return Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFF240B0D),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.error,
                              width: 1.5,
                            ),
                            boxShadow: _isHolding
                                ? [
                                    BoxShadow(
                                      color: AppColors.error.withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : [],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Progress Fill
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: _holdController.value,
                                      child: Container(
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.warning_rounded,
                                      color: _holdController.value > 0.5
                                          ? Colors.white
                                          : AppColors.error,
                                      size: 22,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isSending
                                          ? 'TRANSMITTING...'
                                          : (_isHolding
                                              ? 'HOLD TO SEND (${(3 - (_holdController.value * 3)).toStringAsFixed(1)}s)'
                                              : 'HOLD TO SEND SOS'),
                                      style: TextStyle(
                                        color: _holdController.value > 0.5
                                            ? Colors.white
                                            : AppColors.error,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
