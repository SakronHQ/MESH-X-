import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_x_app/main.dart';
import 'package:mesh_x_app/features/chat/presentation/conversation_list_screen.dart';
import 'package:mesh_x_app/features/mesh/presentation/mesh_nodes_screen.dart';
import 'package:mesh_x_app/features/mesh/presentation/widgets/mesh_topology_graph.dart';
import 'package:mesh_x_app/features/mesh/presentation/widgets/tactical_radar_map.dart';
import 'package:mesh_x_app/features/mesh/presentation/key_exchange_dialog.dart';
import 'package:mesh_x_app/features/device/presentation/device_scanner_screen.dart';
import 'package:mesh_x_app/features/device/presentation/widgets/radio_config_card.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('MeshXApp pumps and navigates all tabs without exception', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MeshXApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Messages tab is visible initially
    expect(find.byType(ConversationListScreen), findsOneWidget);
    expect(find.text('Messages'), findsWidgets);

    // Tap Mesh Topology tab by its icon
    await tester.tap(find.byIcon(Icons.hub_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(MeshNodesScreen), findsOneWidget);
    expect(find.text('Mesh Topology'), findsWidgets);

    // Verify view toggle tabs in MeshNodesScreen
    expect(find.text('Node List'), findsOneWidget);
    expect(find.text('Visual Graph'), findsOneWidget);
    expect(find.text('Tactical Radar'), findsOneWidget);

    // Tap 'Visual Graph' tab (uses pump because of pulse animation)
    await tester.tap(find.text('Visual Graph'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(MeshTopologyGraph), findsOneWidget);

    // Tap 'Tactical Radar' tab (uses pump because of sweep animation)
    await tester.tap(find.text('Tactical Radar'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(TacticalRadarMap), findsOneWidget);
    expect(find.text('BROADCAST SOS'), findsOneWidget);

    // Switch back to 'Node List' tab
    await tester.tap(find.text('Node List'));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Discovered'), findsOneWidget);

    // Tap Radio Node tab by its icon
    await tester.tap(find.byIcon(Icons.router_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceScannerScreen), findsOneWidget);
    expect(find.text('Pair Radio Node'), findsOneWidget);
    expect(find.text('ESP32 BLE Gateway'), findsOneWidget);
  });

  testWidgets('RadioConfigCard renders and allows tuning RF parameters', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RadioConfigCard(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Radio Transceiver Tuning'), findsOneWidget);
    expect(find.text('Spreading Factor'), findsOneWidget);
    expect(find.text('Carrier Frequency'), findsOneWidget);
    expect(find.text('433.175 MHz'), findsOneWidget);
    expect(find.text('Bandwidth'), findsOneWidget);
    expect(find.text('TX Power'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);

    // Tap 433.775 MHz preset chip
    await tester.tap(find.text('433.775 MHz'));
    await tester.pumpAndSettle();

    // Tap Save Config button while disconnected
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    // Verify user receives local save feedback
    expect(find.textContaining('Configuration saved locally'), findsOneWidget);
  });

  testWidgets('KeyExchangeDialog renders QR identity and camera scan action', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KeyExchangeDialog(),
          ),
        ),
      ),
    );
    await tester.pump();
    
    // Pump until _loadKeys completes and CircularProgressIndicator is gone
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }

    expect(find.text('Cryptography Vault'), findsOneWidget);
    expect(find.text('My Identity Card'), findsOneWidget);
    expect(find.text('Pair Contact Key'), findsOneWidget);

    // Tap 'Pair Contact Key' tab and wait for TabBarView animation
    await tester.tap(find.text('Pair Contact Key'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Scan Contact QR Code with Camera'), findsOneWidget);
    expect(find.text('Activate E2EE Encryption'), findsOneWidget);
  });
}
