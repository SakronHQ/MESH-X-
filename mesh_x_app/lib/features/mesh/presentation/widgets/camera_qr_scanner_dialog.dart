import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/theme/app_colors.dart';

class QrScanResult {
  final String? nodeIdHex;
  final String publicKeyHex;

  const QrScanResult({
    this.nodeIdHex,
    required this.publicKeyHex,
  });
}

class CameraQrScannerDialog extends StatefulWidget {
  const CameraQrScannerDialog({super.key});

  static Future<QrScanResult?> show(BuildContext context) {
    return showDialog<QrScanResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (_) => const CameraQrScannerDialog(),
    );
  }

  @override
  State<CameraQrScannerDialog> createState() => _CameraQrScannerDialogState();
}

class _CameraQrScannerDialogState extends State<CameraQrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _hasScanned = false;
  bool _torchEnabled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      final result = _parseQrData(raw);
      if (result != null) {
        _hasScanned = true;
        HapticFeedback.heavyImpact();
        try {
          await _controller.stop();
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pop(result);
        }
        break;
      }
    }
  }

  QrScanResult? _parseQrData(String raw) {
    var rawText = raw.trim();
    String? nodeIdHex;
    String? keyHex;

    if (rawText.startsWith('meshx://')) {
      final uri = Uri.tryParse(rawText);
      if (uri != null) {
        final pub = uri.queryParameters['pub'];
        final id = uri.queryParameters['id'];
        if (pub != null) keyHex = pub;
        if (id != null) nodeIdHex = id;
      }
    } else {
      keyHex = rawText;
    }

    if (keyHex != null) {
      final cleanKey = keyHex.replaceAll(':', '').replaceAll(' ', '').trim();
      if (cleanKey.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(cleanKey)) {
        return QrScanResult(
          nodeIdHex: nodeIdHex,
          publicKeyHex: cleanKey.toLowerCase(),
        );
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 540),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: AppColors.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Scan Contact Identity QR',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Instant Curve25519 public key pairing',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _torchEnabled ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _torchEnabled ? AppColors.accent : AppColors.textMuted,
                        size: 20,
                      ),
                      tooltip: 'Toggle Flashlight',
                      onPressed: () async {
                        await _controller.toggleTorch();
                        setState(() => _torchEnabled = !_torchEnabled);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Viewfinder / Camera
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _handleBarcode,
                      errorBuilder: (context, error) {
                        return Container(
                          color: AppColors.surfaceElevated,
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.videocam_off_rounded,
                                size: 48,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Camera Unavailable',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Camera hardware is not accessible on this device platform (${error.errorDetails?.message ?? "Device simulator or permission denied"}).',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: AppColors.background,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.paste_rounded, size: 16),
                                label: const Text('Paste Key Instead'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    // Reticle overlay
                    Center(
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.accent, width: 2.5),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),

                    // Scanning instruction pill
                    Positioned(
                      bottom: 20,
                      left: 30,
                      right: 30,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Align contact\'s Identity QR inside frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Cancel Button
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    foregroundColor: AppColors.textMuted,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel Scan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
