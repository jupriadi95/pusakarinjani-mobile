import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/nilai.dart';
import '../services/api_service.dart';

/// Nilai list state — holds all score entries for the current match.
final nilaiListProvider =
    StateNotifierProvider<NilaiListNotifier, List<Nilai>>((ref) {
  return NilaiListNotifier();
});

class NilaiListNotifier extends StateNotifier<List<Nilai>> {
  NilaiListNotifier() : super([]);

  final _api = ApiService();

  /// Fetch all nilai for both athletes in the current match.
  /// Equivalent to Nuxt monitor's findNilai().
  Future<void> fetchNilai(String atlit1Id, String atlit2Id) async {
    try {
      final response = await _api.findProtect('nilais', params: {
        'filters[peserta][documentId][\$in][0]': atlit1Id,
        'filters[peserta][documentId][\$in][1]': atlit2Id,
        'populate': 'peserta',
      });
      final data = response['data'] as List? ?? [];
      state = data
          .map((e) => Nilai.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Keep existing state on error
    }
  }

  /// Add a new nilai from WebSocket event.
  /// Checks for duplicates before adding (same as Nuxt monitor).
  void addFromSocket(Nilai newNilai) {
    final isExist = state.any((n) => n.id == newNilai.id);
    if (!isExist) {
      state = [newNilai, ...state];
    }
  }

  /// Create a new nilai via API.
  /// Equivalent to Nuxt juri's addNilai().
  Future<bool> createNilai({
    required int jumlah,
    required String pesertaDocId,
  }) async {
    try {
      await _api.createProtect('nilais', {
        'data': {
          'jumlah': jumlah,
          'peserta': pesertaDocId,
          'menit_ke': '03:01:02',
        },
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Clear all nilai
  void clear() {
    state = [];
  }
}

/// Computed: Total score for atlit 1
int countNilaiForPeserta(List<Nilai> allNilai, String pesertaDocId) {
  return allNilai
      .where((n) => n.peserta?.documentId == pesertaDocId)
      .fold(0, (sum, n) => sum + (n.jumlah ?? 0));
}

/// Computed: Recent score logs for a specific peserta (last 4)
List<Nilai> recentNilaiForPeserta(List<Nilai> allNilai, String pesertaDocId) {
  final filtered = allNilai
      .where((n) => n.peserta?.documentId == pesertaDocId)
      .toList();
  filtered.sort((a, b) {
    final aTime = a.createdAt ?? DateTime(2000);
    final bTime = b.createdAt ?? DateTime(2000);
    return bTime.compareTo(aTime);
  });
  return filtered.take(4).toList();
}
