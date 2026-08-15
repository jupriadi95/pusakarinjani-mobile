import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/jadwal.dart';
import '../models/gelanggang.dart';
import '../services/api_service.dart';

/// Jadwal list provider — fetches match schedules for a gelanggang.
/// Equivalent to Nuxt operator's fetchJadwal().
final jadwalListProvider =
    StateNotifierProvider<JadwalListNotifier, AsyncValue<List<Jadwal>>>((ref) {
  return JadwalListNotifier();
});

class JadwalListNotifier extends StateNotifier<AsyncValue<List<Jadwal>>> {
  JadwalListNotifier() : super(const AsyncValue.data([]));

  final _api = ApiService();

  /// Fetch jadwal list for a specific gelanggang.
  /// Mirrors the complex fetching logic in operator/index.vue
  Future<void> fetchJadwal(Gelanggang gelanggang) async {
    state = const AsyncValue.loading();
    try {
      final eventId = gelanggang.event?.documentId ??
          gelanggang.event?.id?.toString() ??
          '';

      List<Jadwal> allJadwals = [];

      // 1. Try custom backend endpoint GET /jadwal/event/:eventId
      if (eventId.isNotEmpty) {
        try {
          final customResult = await _api.fetchJadwalByEvent(eventId);
          allJadwals = customResult
              .map((e) => Jadwal.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (err) {
          debugPrint('GET /jadwal/event failed: $err');
        }
      }

      // 2. Fallback to standard Strapi findProtect
      if (allJadwals.isEmpty) {
        final Map<String, dynamic> params = {
          'populate[0]': 'gelanggang',
          'populate[1]': 'kelas',
          'populate[2]': 'atlit_merah',
          'populate[3]': 'atlit_biru',
          'populate[4]': 'peserta_1',
          'populate[5]': 'peserta_2',
          'populate[6]': 'pemenang',
          'populate[7]': 'event',
        };
        if (eventId.isNotEmpty) {
          params['filters[event][documentId][\$eq]'] = eventId;
        }

        final response = await _api.findProtect('jadwals', params: params);
        final data = response['data'] as List? ?? [];
        allJadwals =
            data.map((e) => Jadwal.fromJson(e as Map<String, dynamic>)).toList();
      }

      // 3. Filter matches for current Gelanggang
      final targetDocId = gelanggang.documentId ?? '';
      final targetId = gelanggang.id?.toString() ?? '';
      final targetKode =
          (gelanggang.kodeGelanggang ?? '').toLowerCase().trim();

      List<Jadwal> arenaMatches = allJadwals.where((j) {
        if (j.gelanggang == null) return false;
        final g = j.gelanggang!;
        final gDocId = g.documentId ?? '';
        final gId = g.id?.toString() ?? '';
        final gKode = (g.kodeGelanggang ?? '').toLowerCase().trim();

        return (targetDocId.isNotEmpty && gDocId == targetDocId) ||
            (targetId.isNotEmpty && gId == targetId) ||
            (targetKode.isNotEmpty && gKode == targetKode) ||
            (targetKode.isNotEmpty && gKode.contains(targetKode));
      }).toList();

      // Fallback: if no arena-specific matches, show all so operator still has access
      if (arenaMatches.isEmpty) {
        arenaMatches = allJadwals;
      }

      // Sort by nomor_partai ascending
      arenaMatches.sort((a, b) {
        final aNum = int.tryParse(a.nomorPartai?.toString() ?? '0') ?? 0;
        final bNum = int.tryParse(b.nomorPartai?.toString() ?? '0') ?? 0;
        return aNum.compareTo(bNum);
      });

      state = AsyncValue.data(arenaMatches);
    } catch (e, st) {
      debugPrint('Error fetching operator jadwal: $e');
      state = AsyncValue.error(e, st);
    }
  }
}

/// Selected jadwal provider
final selectedJadwalProvider = StateProvider<Jadwal?>((ref) => null);
