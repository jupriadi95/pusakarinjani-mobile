import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/gelanggang.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Active gelanggang state — equivalent to Nuxt's useGelanggangStore
final activeGelanggangProvider =
    StateNotifierProvider<ActiveGelanggangNotifier, Gelanggang?>((ref) {
  return ActiveGelanggangNotifier();
});

class ActiveGelanggangNotifier extends StateNotifier<Gelanggang?> {
  ActiveGelanggangNotifier() : super(null) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    final saved = await StorageService.loadActiveGelanggang();
    if (saved != null) {
      state = saved;
    }
  }

  /// Set active gelanggang (same as Pinia store's setEvent)
  Future<void> setGelanggang(Gelanggang gelanggang) async {
    state = gelanggang;
    await StorageService.saveActiveGelanggang(gelanggang);
  }

  /// Update gelanggang from WebSocket event
  void updateFromSocket(Gelanggang updated) {
    state = updated;
  }

  /// Clear active gelanggang
  Future<void> clear() async {
    state = null;
    await StorageService.clearActiveGelanggang();
  }
}

/// Verify gelanggang by code — API call
/// Equivalent to Nuxt's verify.vue verifyCode()
final verifyGelanggangProvider =
    FutureProvider.family<Gelanggang?, String>((ref, code) async {
  final api = ApiService();
  final response = await api.findProtect('gelanggangs', params: {
    'filters[kode_gelanggang][\$eq]': code,
    'populate[0]': 'event',
    'populate[1]': 'event.cover',
  });

  final data = response['data'] as List?;
  if (data != null && data.isNotEmpty) {
    return Gelanggang.fromJson(data[0] as Map<String, dynamic>);
  }
  return null;
});
