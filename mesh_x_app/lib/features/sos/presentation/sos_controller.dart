import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../chat/presentation/chat_controller.dart';
import '../domain/sos_alert_model.dart';

final sosAlertStreamProvider = StreamProvider<SosAlertModel>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  return repo.sosAlertStream;
});

class ActiveSosAlertNotifier extends Notifier<SosAlertModel?> {
  @override
  SosAlertModel? build() {
    ref.listen(sosAlertStreamProvider, (prev, next) {
      if (next.hasValue && next.value != null) {
        state = next.value;
      }
    });
    return null;
  }

  void setAlert(SosAlertModel alert) {
    state = alert;
  }

  void dismissAlert() {
    state = null;
  }
}

final activeSosAlertProvider =
    NotifierProvider<ActiveSosAlertNotifier, SosAlertModel?>(() {
  return ActiveSosAlertNotifier();
});
