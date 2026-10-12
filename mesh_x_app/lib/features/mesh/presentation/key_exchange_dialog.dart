import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../chat/presentation/chat_controller.dart';
import '../../device/presentation/ble_controller.dart';

class KeyExchangeDialog extends ConsumerStatefulWidget {
  final int? peerNodeId;

  const KeyExchangeDialog({super.key, this.peerNodeId});

  @override
  ConsumerState<KeyExchangeDialog> createState() => _KeyExchangeDialogState();
}

class _KeyExchangeDialogState extends ConsumerState<KeyExchangeDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _keyInputController = TextEditingController();
  final _nodeIdInputController = TextEditingController();
  String? _myPubKeyHex;
  String? _myFingerprint;
  bool _isLoading = true;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.peerNodeId != null && widget.peerNodeId != 0xFFFFFFFF) {
      _nodeIdInputController.text =
          '0x${widget.peerNodeId!.toRadixString(16).padLeft(8, '0').toUpperCase()}';
    }
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final chatRepo = ref.read(chatRepositoryProvider);
    final pubHex = await chatRepo.cryptoService.getMyPublicKeyHex();
    final fingerprint = await chatRepo.cryptoService.getMyFingerprint();

    // Check if peer already has a key
    if (widget.peerNodeId != null && widget.peerNodeId != 0xFFFFFFFF) {
      final existingKey = await chatRepo.getPeerPublicKey(widget.peerNodeId!);
      if (existingKey != null) {
        _keyInputController.text = existingKey;
      }
    }

    if (mounted) {
      setState(() {
        _myPubKeyHex = pubHex;
        _myFingerprint = fingerprint;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _keyInputController.dispose();
    _nodeIdInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleControllerProvider);
    final myNodeId = bleState.deviceInfo?.nodeId ?? 0;
    final myNodeHex = '0x${myNodeId.toRadixString(16).padLeft(8, '0').toUpperCase()}';

    final qrData = 'meshx://key?id=$myNodeHex&pub=$_myPubKeyHex';

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.accent, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'End-to-End Cryptography',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.accent,
              labelColor: AppColors.accent,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              tabs: const [
                Tab(text: 'My Identity Card'),
                Tab(text: 'Pair Contact Key'),
              ],
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildMyIdentityTab(qrData, myNodeHex),
                        _buildPairContactTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyIdentityTab(String qrData, String myNodeHex) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // QR Code Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 160.0,
            ),
          ),
          const SizedBox(height: 16),

          // Fingerprint Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text(
                  'FINGERPRINT',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _myFingerprint ?? 'LOADING',
                  style: const TextStyle(
                    fontSize: 16,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Node ID: $myNodeHex (X25519 Curve25519 Key)',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Copy Public Key Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceHighlight,
              foregroundColor: AppColors.accent,
              minimumSize: const Size(double.infinity, 44),
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy 64-char Public Key Hex'),
            onPressed: () {
              if (_myPubKeyHex != null) {
                Clipboard.setData(ClipboardData(text: _myPubKeyHex!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Public key hex copied to clipboard!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPairContactTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pair Contact Public Key',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Paste peer\'s 64-character public key hex to enable ChaCha20-Poly1305 authenticated end-to-end encryption.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),

          // Node ID Field
          TextField(
            controller: _nodeIdInputController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Peer Node ID (Hex e.g. 0xA1B2C3D4)',
              labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Public Key Hex Field
          TextField(
            controller: _keyInputController,
            maxLines: 3,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              labelText: 'Peer 32-Byte Public Key (64 Hex Characters)',
              labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.connected.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.connected.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: AppColors.connected),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(fontSize: 12, color: AppColors.connected),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Save Key Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.background,
              minimumSize: const Size(double.infinity, 44),
            ),
            icon: const Icon(Icons.lock, size: 18),
            label: const Text(
              'Activate E2EE for Contact',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _saveContactKey,
          ),
        ],
      ),
    );
  }

  Future<void> _saveContactKey() async {
    final keyHex = _keyInputController.text.replaceAll(':', '').replaceAll(' ', '').trim();
    final nodeStr = _nodeIdInputController.text.trim();

    if (keyHex.length != 64) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid key length: ${keyHex.length} chars (expected 64).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    int? targetNodeId;
    if (nodeStr.startsWith('0x') || nodeStr.startsWith('0X')) {
      targetNodeId = int.tryParse(nodeStr.substring(2), radix: 16);
    } else {
      targetNodeId = int.tryParse(nodeStr);
    }

    if (targetNodeId == null || targetNodeId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid Peer Node ID.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final chatRepo = ref.read(chatRepositoryProvider);
    await chatRepo.setPeerPublicKey(targetNodeId, keyHex, isVerified: true);

    setState(() {
      _statusMessage = 'Key verified! Messages to this node are now end-to-end encrypted.';
    });
  }
}
