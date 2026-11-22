import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/radio_config_model.dart';
import '../ble_controller.dart';

class RadioConfigCard extends ConsumerStatefulWidget {
  const RadioConfigCard({super.key});

  @override
  ConsumerState<RadioConfigCard> createState() => _RadioConfigCardState();
}

class _RadioConfigCardState extends ConsumerState<RadioConfigCard> {
  late double _frequencyMhz;
  late int _spreadingFactor;
  late double _bandwidthKhz;
  late int _codingRate;
  late int _txPowerDbm;
  bool _isSaving = false;
  bool _isUserEditing = false;

  final List<double> _frequencyPresets = [
    433.175,
    433.375,
    433.775,
    434.175,
    868.100,
    915.000,
  ];

  @override
  void initState() {
    super.initState();
    final cfg = ref.read(bleControllerProvider).radioConfig;
    _loadFromConfig(cfg);
  }

  void _loadFromConfig(RadioConfigModel cfg) {
    _frequencyMhz = cfg.frequencyMhz;
    _spreadingFactor = cfg.spreadingFactor;
    _bandwidthKhz = cfg.bandwidthKhz;
    _codingRate = cfg.codingRate;
    _txPowerDbm = cfg.txPowerDbm;
  }

  RadioConfigModel get _currentSelection => RadioConfigModel(
        frequencyMhz: _frequencyMhz,
        spreadingFactor: _spreadingFactor,
        bandwidthKhz: _bandwidthKhz,
        codingRate: _codingRate,
        txPowerDbm: _txPowerDbm,
      );

  @override
  Widget build(BuildContext context) {
    ref.listen<RadioConfigModel>(
      bleControllerProvider.select((s) => s.radioConfig),
      (prev, next) {
        if (!_isUserEditing && mounted) {
          setState(() {
            _loadFromConfig(next);
          });
        }
      },
    );

    final bleState = ref.watch(bleControllerProvider);
    final isConnected = bleState.isConnected;
    final toa = _currentSelection.estimateTimeToAirMs();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.settings_input_antenna_rounded,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Radio Transceiver Tuning',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'LoRa PHY link & RF modulation parameters',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // ToA Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'ToA: ${toa}ms',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    color: AppColors.accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Spreading Factor Slider (SF7 - SF12)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Spreading Factor',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SF$_spreadingFactor',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.accent,
              inactiveTrackColor: AppColors.surfaceHighlight,
              thumbColor: AppColors.accent,
              overlayColor: AppColors.accent.withValues(alpha: 0.15),
              trackHeight: 4,
            ),
            child: Slider(
              value: _spreadingFactor.toDouble(),
              min: 7,
              max: 12,
              divisions: 5,
              onChanged: (val) {
                HapticFeedback.selectionClick();
                setState(() {
                  _isUserEditing = true;
                  _spreadingFactor = val.round();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _currentSelection.speedModeDescription,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Frequency Selection
          const Text(
            'Carrier Frequency',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _frequencyPresets.map((freq) {
              final isSelected = (_frequencyMhz - freq).abs() < 0.001;
              return ChoiceChip(
                label: Text('${freq.toStringAsFixed(3)} MHz'),
                selected: isSelected,
                selectedColor: AppColors.accent.withValues(alpha: 0.2),
                backgroundColor: AppColors.surfaceElevated,
                labelStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.accent : AppColors.textSecondary,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? AppColors.accent : AppColors.border,
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isUserEditing = true;
                      _frequencyMhz = freq;
                    });
                  }
                },
              );
            }).toList(),
          ),

          if (_frequencyMhz >= 800.0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Notice: RA-02 operates on 433 MHz band. 868/915 MHz requires SX1276/SX1262 hardware.',
                      style: TextStyle(fontSize: 10, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // TX Power & Bandwidth Row
          Row(
            children: [
              // Bandwidth
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bandwidth',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _bandwidthKhz,
                          dropdownColor: AppColors.surfaceElevated,
                          isExpanded: true,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          items: const [
                            DropdownMenuItem(value: 125.0, child: Text('125 kHz')),
                            DropdownMenuItem(value: 250.0, child: Text('250 kHz')),
                            DropdownMenuItem(value: 500.0, child: Text('500 kHz')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _isUserEditing = true;
                                _bandwidthKhz = val;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // TX Power
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TX Power',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '$_txPowerDbm dBm',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: AppColors.accent,
                        inactiveTrackColor: AppColors.surfaceHighlight,
                        thumbColor: AppColors.accent,
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _txPowerDbm.toDouble(),
                        min: 2,
                        max: 20,
                        divisions: 18,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isUserEditing = true;
                            _txPowerDbm = val.round();
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Apply Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.background,
                      ),
                    )
                  : const Icon(Icons.tune_rounded, size: 18),
              label: Text(
                _isSaving
                    ? 'Updating ESP32 Radio...'
                    : (isConnected ? 'Apply Radio Settings' : 'Save Config (Connect to Sync)'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: _isSaving
                  ? null
                  : () async {
                      HapticFeedback.mediumImpact();
                      _isUserEditing = false;
                      setState(() => _isSaving = true);
                      final controller = ref.read(bleControllerProvider.notifier);
                      final ok = await controller.updateRadioConfig(_currentSelection);
                      if (context.mounted) {
                        setState(() => _isSaving = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'LoRa radio tuned: ${_frequencyMhz.toStringAsFixed(3)} MHz (SF$_spreadingFactor, ${_bandwidthKhz.round()}kHz, $_txPowerDbm dBm)'
                                  : 'Configuration saved locally (ESP32 node not connected).',
                            ),
                            backgroundColor: ok ? AppColors.connected : AppColors.surfaceElevated,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }
}
