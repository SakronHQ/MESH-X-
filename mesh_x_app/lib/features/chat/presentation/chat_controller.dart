import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../device/presentation/ble_controller.dart';
import '../../mesh/domain/mesh_node_model.dart';
import '../data/chat_repository.dart';
import '../domain/conversation_model.dart';
import '../domain/message_model.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final bleRepo = ref.watch(bleRepositoryProvider);
  final chatRepo = ChatRepository(bleRepo);
  ref.onDispose(chatRepo.dispose);
  return chatRepo;
});

// Stream of Conversations
final conversationsProvider =
    StreamProvider<List<ConversationModel>>((ref) async* {
  final repo = ref.watch(chatRepositoryProvider);
  // Initial load
  final initial = await repo.getConversations();
  yield initial;

  // Stream updates
  await for (final convs in repo.conversationsStream) {
    yield convs;
  }
});

// Stream of Messages for a specific conversation
final messagesProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, convId) async* {
  final repo = ref.watch(chatRepositoryProvider);
  final initial = await repo.getMessages(convId);
  yield initial;

  await for (final updatedConvId in repo.messagesUpdateStream) {
    if (updatedConvId == convId) {
      final updated = await repo.getMessages(convId);
      yield updated;
    }
  }
});

// Stream of Discovered Mesh Nodes
final discoveredNodesProvider =
    StreamProvider<List<MeshNodeModel>>((ref) async* {
  final repo = ref.watch(chatRepositoryProvider);
  final initial = await repo.getDiscoveredNodes();
  yield initial;

  await for (final nodes in repo.nodesStream) {
    yield nodes;
  }
});
