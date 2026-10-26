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
        borderRadius: BorderRadius.circular(24),
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
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Cryptography Vault',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: AppColors.accent,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                padding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(text: 'My Identity Card'),
                  Tab(text: 'Pair Contact Key'),
                ],
              ),
            ),

            // Tab Views
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    )
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
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 150.0,
            ),
          ),
          const SizedBox(height: 18),

          // Fingerprint Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text(
                  'SECURITY FINGERPRINT',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _myFingerprint ?? 'LOADING...',
                  style: const TextStyle(
                    fontSize: 15,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Node ID: $myNodeHex • Curve25519 (X25519)',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),

          // Copy Public Key Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.surfaceHighlight,
              foregroundColor: AppColors.accent,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text(
              'Copy 64-Hex Public Key',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              if (_myPubKeyHex != null) {
                HapticFeedback.lightImpact();
                Clipboard.setData(ClipboardData(text: _myPubKeyHex!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Public key hex copied to clipboard'),
                    duration: Duration(seconds: 1),
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
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Paste peer\'s 64-hex public key to enable ChaCha20-Poly1305 end-to-end encryption.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 16),

          // Node ID Field
          TextField(
            controller: _nodeIdInputController,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: 'Peer Node ID (e.g. 0xA1B2C3D4)',
              labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              prefixIcon: const Icon(Icons.tag_rounded, size: 18, color: AppColors.textMuted),
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
              labelText: 'Peer Public Key (64 Hex Characters)',
              labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              filled: true,
              fillColor: AppColors.surfaceElevated,
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste_rounded, size: 18, color: AppColors.accent),
                tooltip: 'Paste from Clipboard',
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data != null && data.text != null) {
                    _keyInputController.text = data.text!.trim();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_statusMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.connected.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.connected.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.connected),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.connected,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Save Key Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.lock_rounded, size: 18),
            label: const Text(
              'Activate E2EE Encryption',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              _saveContactKey();
            },
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

