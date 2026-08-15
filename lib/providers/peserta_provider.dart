import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/peserta.dart';
import '../services/api_service.dart';

/// Peserta provider — fetches athlete data by documentId.
/// Equivalent to Nuxt's fetchPeserta(docId, dst).
final pesertaByIdProvider =
    FutureProvider.family<Peserta?, String>((ref, docId) async {
  if (docId.isEmpty) return null;
  final api = ApiService();
  try {
    final response = await api.findOneProtect('pesertas', docId, params: {
      'populate[0]': 'action_foto',
      'populate[1]': 'pas_foto',
      'populate[2]': 'kelas',
    });
    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return Peserta.fromJson(data);
    }
    return null;
  } catch (e) {
    return null;
  }
});

/// Atlit 1 (Sudut Biru / Peserta 1) state
final atlit1Provider = StateProvider<Peserta?>((ref) => null);

/// Atlit 2 (Sudut Merah / Peserta 2) state
final atlit2Provider = StateProvider<Peserta?>((ref) => null);

/// All peserta for the event (used in operator manual search fallback)
final eventPesertaListProvider =
    FutureProvider.family<List<Peserta>, String>((ref, eventDocId) async {
  if (eventDocId.isEmpty) return [];
  final api = ApiService();
  try {
    final response = await api.findProtect('pesertas', params: {
      'filters[event][documentId][\$eq]': eventDocId,
    });
    final data = response['data'] as List? ?? [];
    return data
        .map((e) => Peserta.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    return [];
  }
});
