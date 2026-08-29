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
  /// Merges authoritative server data with optimistic local scores so points never disappear.
  Future<void> fetchNilai(
    String atlit1Id,
    String atlit2Id, {
    String? atlit1AltId,
    String? atlit2AltId,
    String? jadwalDocId,
    String? jadwalId,
  }) async {
    final hasAthletes = atlit1Id.isNotEmpty ||
        atlit2Id.isNotEmpty ||
        (atlit1AltId != null && atlit1AltId.isNotEmpty) ||
        (atlit2AltId != null && atlit2AltId.isNotEmpty);
    final hasJadwal = (jadwalDocId != null && jadwalDocId.isNotEmpty) ||
        (jadwalId != null && jadwalId.isNotEmpty);

    if (!hasAthletes && !hasJadwal) {
      state = [];
      return;
    }

    try {
      final params = <String, dynamic>{
        'populate': '*',
        'sort': 'createdAt:desc',
        'pagination[limit]': 100,
        'filters[status][\$ne]': 'ditolak',
      };

      if (jadwalDocId != null && jadwalDocId.isNotEmpty) {
        params['filters[jadwal][documentId]'] = jadwalDocId;
      } else if (jadwalId != null && jadwalId.isNotEmpty) {
        params['filters[jadwal][id]'] = jadwalId;
      }

      final response = await _api.findProtect('nilais', params: params);
      final data = response['data'] as List? ?? [];
      final fetchedList = data
          .map((e) => Nilai.fromJson(e as Map<String, dynamic>))
          .where((n) => n.isSah)
          .toList();

      // Filter scores that strictly belong to this match and atlit1 or atlit2
      final filteredList = fetchedList.where((n) {
        // 1. Strict Jadwal filter if score entry has a recorded match reference
        if (hasJadwal) {
          if (n.jadwalDocId != null &&
              n.jadwalDocId!.isNotEmpty &&
              jadwalDocId != null &&
              jadwalDocId.isNotEmpty) {
            if (n.jadwalDocId != jadwalDocId) return false;
          }
          if (n.jadwalId != null &&
              n.jadwalId!.isNotEmpty &&
              jadwalId != null &&
              jadwalId.isNotEmpty) {
            if (n.jadwalId != jadwalId) return false;
          }
        }

        // 2. Athlete ID matching
        final doc = n.peserta?.documentId;
        final id = n.peserta?.id?.toString();
        final matchesA1 = (atlit1Id.isNotEmpty &&
                (doc == atlit1Id || id == atlit1Id)) ||
            (atlit1AltId != null &&
                atlit1AltId.isNotEmpty &&
                (doc == atlit1AltId || id == atlit1AltId));
        final matchesA2 = (atlit2Id.isNotEmpty &&
                (doc == atlit2Id || id == atlit2Id)) ||
            (atlit2AltId != null &&
                atlit2AltId.isNotEmpty &&
                (doc == atlit2AltId || id == atlit2AltId));

        if (matchesA1 || matchesA2) return true;

        // If score record explicitly belongs to a DIFFERENT athlete, reject it!
        if (n.peserta != null &&
            ((doc != null && doc.isNotEmpty) || (id != null && id.isNotEmpty))) {
          return false;
        }

        // 3. Fallback for unpopulated corner actions (KP actions without athlete object)
        final isBiru = n.sudut?.toLowerCase() == 'biru' &&
            (atlit1Id.isNotEmpty ||
                (atlit1AltId != null && atlit1AltId.isNotEmpty));
        final isMerah = n.sudut?.toLowerCase() == 'merah' &&
            (atlit2Id.isNotEmpty ||
                (atlit2AltId != null && atlit2AltId.isNotEmpty));

        return isBiru || isMerah;
      }).toList();

      // Preserve any optimistic temporary items OR socket-delivered items in state belonging to the current match
      final optimisticPreserved = state.where((item) {
        final isTemporaryOrSocket = (item.documentId == null ||
                item.documentId!.isEmpty) ||
            (item.id != null && item.id! >= 1000000000000) ||
            (item.juriId != null && item.juriId!.isNotEmpty);
        if (!isTemporaryOrSocket) return false;

        if (hasJadwal) {
          if (item.jadwalDocId != null &&
              item.jadwalDocId!.isNotEmpty &&
              jadwalDocId != null &&
              jadwalDocId.isNotEmpty) {
            if (item.jadwalDocId != jadwalDocId) return false;
          }
          if (item.jadwalId != null &&
              item.jadwalId!.isNotEmpty &&
              jadwalId != null &&
              jadwalId.isNotEmpty) {
            if (item.jadwalId != jadwalId) return false;
          }
        }

        final doc = item.peserta?.documentId;
        final id = item.peserta?.id?.toString();
        final matchesA1 = (atlit1Id.isNotEmpty &&
                ((doc != null && doc == atlit1Id) || (id != null && id == atlit1Id))) ||
            (atlit1AltId != null &&
                atlit1AltId.isNotEmpty &&
                ((doc != null && doc == atlit1AltId) || (id != null && id == atlit1AltId)));
        final matchesA2 = (atlit2Id.isNotEmpty &&
                ((doc != null && doc == atlit2Id) || (id != null && id == atlit2Id))) ||
            (atlit2AltId != null &&
                atlit2AltId.isNotEmpty &&
                ((doc != null && doc == atlit2AltId) || (id != null && id == atlit2AltId)));
        final matchesCorner = item.sudut != null &&
            (item.sudut!.toLowerCase() == 'biru' || item.sudut!.toLowerCase() == 'merah');

        if (!matchesA1 && !matchesA2 && !matchesCorner) return false;

        final alreadyInFetched = filteredList.any((f) =>
            (f.documentId != null && f.documentId == item.documentId) ||
            (f.id != null && f.id == item.id) ||
            (f.jenis == item.jenis &&
                f.jumlah == item.jumlah &&
                f.sudut == item.sudut &&
                f.createdAt != null &&
                item.createdAt != null &&
                f.createdAt!
                        .difference(item.createdAt!)
                        .inMilliseconds
                        .abs() <
                    3500));
        return !alreadyInFetched;
      }).toList();

      final combined = [...optimisticPreserved, ...filteredList];
      combined.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(2000);
        final bTime = b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });

      state = combined;
    } catch (e) {
      debugPrint('[NilaiProvider] fetchNilai error: $e');
    }
  }

  /// Add a new nilai from WebSocket event or local optimistic action.
  /// Replaces temporary optimistic items with server confirmed items without dropping consecutive actions.
  void addFromSocket(Nilai newNilai) {
    if (newNilai.isDitolak) return; // Ignore rejected votes

    final list = [...state];
    int existingIdx = -1;

    final isNewServer = (newNilai.documentId != null && newNilai.documentId!.isNotEmpty) ||
                        (newNilai.id != null && newNilai.id! < 1000000000000);

    for (int i = 0; i < list.length; i++) {
      final n = list[i];

      // 1. Exact ID match (both server records or both matching temporary IDs)
      if (newNilai.documentId != null && n.documentId != null && newNilai.documentId == n.documentId) {
        existingIdx = i;
        break;
      }
      if (newNilai.id != null && n.id != null && newNilai.id == n.id) {
        existingIdx = i;
        break;
      }

      // 2. Reconcile temporary optimistic item with newly arrived server record
      final isExistingOptimistic = (n.documentId == null || n.documentId!.isEmpty) &&
                                   (n.id != null && n.id! >= 1000000000000);

      if (isExistingOptimistic && isNewServer) {
        final samePeserta = (n.peserta?.documentId != null && n.peserta?.documentId == newNilai.peserta?.documentId) ||
                            (n.peserta?.id != null && n.peserta?.id == newNilai.peserta?.id);
        final sameSudut = (n.sudut != null && newNilai.sudut != null && n.sudut == newNilai.sudut);
        final sameType = (n.jenis?.toLowerCase() == newNilai.jenis?.toLowerCase() ||
                          ((n.jenis == 'batal_jatuhan' || n.jenis == 'jatuhan') &&
                           (newNilai.jenis == 'batal_jatuhan' || newNilai.jenis == 'jatuhan') &&
                           n.jumlah == newNilai.jumlah)) &&
                         n.jumlah == newNilai.jumlah;

        if ((samePeserta || sameSudut) && sameType) {
          if (n.createdAt != null && newNilai.createdAt != null) {
            final diff = n.createdAt!.difference(newNilai.createdAt!).inMilliseconds.abs();
            if (diff < 3000) {
              existingIdx = i;
              break;
            }
          } else {
            existingIdx = i;
            break;
          }
        }
      }
    }

    if (existingIdx >= 0) {
      // Preserve existing athlete object if new incoming record has null relation
      final existingPeserta = list[existingIdx].peserta;
      final resolvedPeserta = newNilai.peserta ?? existingPeserta;
      list[existingIdx] = Nilai(
        id: newNilai.id ?? list[existingIdx].id,
        documentId: newNilai.documentId ?? list[existingIdx].documentId,
        peserta: resolvedPeserta,
        jumlah: newNilai.jumlah ?? list[existingIdx].jumlah,
        menitKe: newNilai.menitKe ?? list[existingIdx].menitKe,
        jenis: newNilai.jenis ?? list[existingIdx].jenis,
        status: newNilai.status ?? list[existingIdx].status,
        sudut: newNilai.sudut ?? list[existingIdx].sudut,
        juriId: newNilai.juriId ?? list[existingIdx].juriId,
        juriCount: newNilai.juriCount ?? list[existingIdx].juriCount,
        babak: newNilai.babak ?? list[existingIdx].babak,
        createdAt: newNilai.createdAt ?? list[existingIdx].createdAt,
      );
      state = [...list];
    } else {
      state = [newNilai, ...list];
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
int countNilaiForPeserta(
  List<Nilai> allNilai,
  String pesertaDocId, {
  String? sudut,
}) {
  if (pesertaDocId.isEmpty && (sudut == null || sudut.isEmpty)) return 0;
  return allNilai
      .where((n) {
        if (!n.isSah) return false;
        final doc = n.peserta?.documentId;
        final id = n.peserta?.id?.toString();
        final matchesId = pesertaDocId.isNotEmpty &&
            ((doc != null && doc == pesertaDocId) ||
                (id != null && id == pesertaDocId));
        final matchesSudut = (sudut != null &&
            sudut.isNotEmpty &&
            n.sudut?.toLowerCase() == sudut.toLowerCase());
        return matchesId || matchesSudut;
      })
      .fold(0, (sum, n) => sum + (n.jumlah ?? 0));
}

/// Computed: Recent scores for an athlete (latest first)
List<Nilai> recentNilaiForPeserta(
  List<Nilai> allNilai,
  String pesertaDocId, {
  int limit = 5,
  String? sudut,
}) {
  if (pesertaDocId.isEmpty && (sudut == null || sudut.isEmpty)) return [];
  final filtered = allNilai.where((n) {
    if (!n.isSah) return false;
    final doc = n.peserta?.documentId;
    final id = n.peserta?.id?.toString();
    final matchesId = pesertaDocId.isNotEmpty &&
        ((doc != null && doc == pesertaDocId) ||
            (id != null && id == pesertaDocId));
    final matchesSudut = (sudut != null &&
        sudut.isNotEmpty &&
        n.sudut?.toLowerCase() == sudut.toLowerCase());
    return matchesId || matchesSudut;
  }).toList();
  filtered.sort((a, b) {
    final aTime = a.createdAt ?? DateTime(2000);
    final bTime = b.createdAt ?? DateTime(2000);
    return bTime.compareTo(aTime);
  });
  return filtered.take(limit).toList();
}
