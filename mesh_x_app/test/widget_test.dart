import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mesh_x_app/main.dart';
import 'package:mesh_x_app/features/chat/presentation/conversation_list_screen.dart';
import 'package:mesh_x_app/features/mesh/presentation/mesh_nodes_screen.dart';
import 'package:mesh_x_app/features/device/presentation/device_scanner_screen.dart';

void main() {
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

    // Tap Radio Node tab by its icon
    await tester.tap(find.byIcon(Icons.router_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(DeviceScannerScreen), findsOneWidget);
    expect(find.text('Pair Radio Node'), findsOneWidget);
    expect(find.text('ESP32 BLE Gateway'), findsOneWidget);
  });
}
