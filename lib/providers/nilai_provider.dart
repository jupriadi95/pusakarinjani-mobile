import 'package:flutter/foundation.dart';
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

  /// Fetch all sah (approved) nilai for both athletes in the current match.
  /// Merges with existing state to ensure real-time socket events are never lost.
  Future<void> fetchNilai(String atlit1Id, String atlit2Id) async {
    try {
      final params = <String, dynamic>{
        'populate': 'peserta',
        'sort': 'createdAt:desc',
        'pagination[limit]': 100,
        'filters[status][\$ne]': 'ditolak',
      };

      if (atlit1Id.isNotEmpty && atlit2Id.isNotEmpty) {
        params['filters[\$or][0][peserta][documentId][\$in][0]'] = atlit1Id;
        params['filters[\$or][0][peserta][documentId][\$in][1]'] = atlit2Id;
        params['filters[\$or][1][peserta][id][\$in][0]'] = atlit1Id;
        params['filters[\$or][1][peserta][id][\$in][1]'] = atlit2Id;
      }

      final response = await _api.findProtect('nilais', params: params);
      final data = response['data'] as List? ?? [];
      final fetchedList = data
          .map((e) => Nilai.fromJson(e as Map<String, dynamic>))
          .where((n) => n.isSah)
          .toList();

      if (fetchedList.isEmpty && state.isNotEmpty) {
        // Keep existing in-memory state if server returns empty list (e.g. permission/filter issue)
        return;
      }

      // Merge fetched list with current state
      final merged = <Nilai>[...state];
      for (final item in fetchedList) {
        final idx = merged.indexWhere((n) {
          if (item.documentId != null && n.documentId != null && item.documentId == n.documentId) {
            return true;
          }
          if (item.id != null && n.id != null && item.id == n.id) {
            return true;
          }
          final sameSudut = item.sudut != null && n.sudut != null && item.sudut!.toLowerCase() == n.sudut!.toLowerCase();
          final sameType = item.jenis?.toLowerCase() == n.jenis?.toLowerCase() && item.jumlah == n.jumlah;
          if (sameSudut && sameType && n.createdAt != null && item.createdAt != null) {
            return n.createdAt!.difference(item.createdAt!).inMilliseconds.abs() < 4000;
          }
          return false;
        });

        if (idx >= 0) {
          merged[idx] = item; // Update with authoritative server object
        } else {
          merged.add(item);
        }
      }

      merged.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(2000);
        final bTime = b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      state = merged;
    } catch (e) {
      debugPrint('[NilaiProvider] fetchNilai error (state preserved): $e');
    }
  }

  /// Add a new nilai from WebSocket event or local optimistic action.
  /// Checks for duplicates and replaces optimistic temporary items with server items.
  void addFromSocket(Nilai newNilai) {
    if (newNilai.isDitolak) return; // Ignore rejected votes

    final list = [...state];
    int existingIdx = -1;

    for (int i = 0; i < list.length; i++) {
      final n = list[i];
      if (newNilai.documentId != null && n.documentId != null && newNilai.documentId == n.documentId) {
        existingIdx = i;
        break;
      }
      if (newNilai.id != null && n.id != null && newNilai.id == n.id) {
        existingIdx = i;
        break;
      }
      final samePeserta = (n.peserta?.documentId != null && n.peserta?.documentId == newNilai.peserta?.documentId) ||
                          (n.peserta?.id != null && n.peserta?.id == newNilai.peserta?.id) ||
                          (n.sudut != null && newNilai.sudut != null && n.sudut!.toLowerCase() == newNilai.sudut!.toLowerCase());
      final sameType = n.jenis?.toLowerCase() == newNilai.jenis?.toLowerCase() && n.jumlah == newNilai.jumlah;
      if (samePeserta && sameType && n.createdAt != null && newNilai.createdAt != null) {
        final diff = n.createdAt!.difference(newNilai.createdAt!).inMilliseconds.abs();
        if (diff < 4000) {
          existingIdx = i;
          break;
        }
      }
    }

    if (existingIdx >= 0) {
      list[existingIdx] = newNilai;
      state = list;
    } else {
      state = [newNilai, ...state];
    }
  }

  /// Create a new nilai via API.
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
          'status': 'sah',
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

/// Computed: Total score for an athlete (only counting SAH points, matching by DocId, Id, or Corner)
int countNilaiForPeserta(List<Nilai> allNilai, String pesertaDocId, {String? sudut}) {
  return allNilai
      .where((n) {
        if (!n.isSah) return false;
        if (pesertaDocId.isNotEmpty) {
          if (n.peserta?.documentId == pesertaDocId || n.peserta?.id?.toString() == pesertaDocId) {
            return true;
          }
        }
        if (sudut != null && n.sudut != null && n.sudut!.toLowerCase() == sudut.toLowerCase()) {
          return true;
        }
        return false;
      })
      .fold(0, (sum, n) => sum + (n.jumlah ?? 0));
}

/// Computed: Recent score logs for a specific peserta (only SAH points, default 5 latest)
List<Nilai> recentNilaiForPeserta(List<Nilai> allNilai, String pesertaDocId, {String? sudut, int limit = 5}) {
  final filtered = allNilai
      .where((n) {
        if (!n.isSah) return false;
        if (pesertaDocId.isNotEmpty) {
          if (n.peserta?.documentId == pesertaDocId || n.peserta?.id?.toString() == pesertaDocId) {
            return true;
          }
        }
        if (sudut != null && n.sudut != null && n.sudut!.toLowerCase() == sudut.toLowerCase()) {
          return true;
        }
        return false;
      })
      .toList();
  filtered.sort((a, b) {
    final aTime = a.createdAt ?? DateTime(2000);
    final bTime = b.createdAt ?? DateTime(2000);
    return bTime.compareTo(aTime);
  });
  return filtered.take(limit).toList();
}
