import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/jadwal.dart';
import '../models/gelanggang.dart';
import '../services/api_service.dart';

/// Jadwal list provider — fetches match schedules for a gelanggang.
final jadwalListProvider =
    StateNotifierProvider<JadwalListNotifier, AsyncValue<List<Jadwal>>>((ref) {
  return JadwalListNotifier();
});

class JadwalListNotifier extends StateNotifier<AsyncValue<List<Jadwal>>> {
  JadwalListNotifier() : super(const AsyncValue.data([]));

  final _api = ApiService();

  /// Fetch jadwal list directly and quickly from Strapi REST API.
  Future<void> fetchJadwal(Gelanggang gelanggang) async {
    state = const AsyncValue.loading();
    try {
      final targetDocId = gelanggang.documentId ?? '';
      final targetId = gelanggang.id?.toString() ?? '';
      final eventDocId = gelanggang.event?.documentId ??
          gelanggang.event?.id?.toString() ??
          '';

      // Use standard Strapi populate=* and pagination to avoid 400 Bad Request on invalid relation keys
      final Map<String, dynamic> params = {
        'populate': '*',
        'pagination[pageSize]': '100',
        'sort[0]': 'nomor_partai:asc',
      };

      final response = await _api.findProtect('jadwals', params: params);
      final data = response['data'] as List? ?? [];
      final allJadwals =
          data.map((e) => Jadwal.fromJson(e as Map<String, dynamic>)).toList();

      debugPrint('Total jadwals fetched from Strapi: ${allJadwals.length}');

      // Filter matches for the active gelanggang
      final targetKode = (gelanggang.kodeGelanggang ?? '').toLowerCase().trim();
      final targetKeterangan = (gelanggang.keterangan ?? '').toLowerCase().trim();

      List<Jadwal> arenaMatches = allJadwals.where((j) {
        if (j.gelanggang == null) return false;
        final g = j.gelanggang!;
        final gDocId = g.documentId ?? '';
        final gId = g.id?.toString() ?? '';
        final gKode = (g.kodeGelanggang ?? '').toLowerCase().trim();
        final gKet = (g.keterangan ?? '').toLowerCase().trim();

        final matchDoc = targetDocId.isNotEmpty && (gDocId == targetDocId || gDocId.contains(targetDocId));
        final matchId = targetId.isNotEmpty && gId == targetId;
        final matchKode = targetKode.isNotEmpty && (gKode == targetKode || gKode.contains(targetKode));
        final matchKet = targetKeterangan.isNotEmpty && (gKet == targetKeterangan || gKet.contains(targetKeterangan));

        return matchDoc || matchId || matchKode || matchKet;
      }).toList();

      // If no specific match was tagged with this specific gelanggang,
      // fallback to showing all event matches so the operator can always select!
      if (arenaMatches.isEmpty) {
        if (eventDocId.isNotEmpty) {
          final eventMatches = allJadwals.where((j) {
            final eDoc = j.event?.documentId ?? j.event?.id?.toString() ?? '';
            return eDoc == eventDocId || eDoc.isEmpty;
          }).toList();
          arenaMatches = eventMatches.isNotEmpty ? eventMatches : allJadwals;
        } else {
          arenaMatches = allJadwals;
        }
      }

      // Sort by nomor_partai ascending
      arenaMatches.sort((a, b) {
        final aNum = int.tryParse(a.nomorPartai?.toString() ?? '0') ?? 0;
        final bNum = int.tryParse(b.nomorPartai?.toString() ?? '0') ?? 0;
        return aNum.compareTo(bNum);
      });

      debugPrint('Final filtered arena matches: ${arenaMatches.length}');
      state = AsyncValue.data(arenaMatches);
    } catch (e, st) {
      debugPrint('Error fetching operator jadwal: $e');
      state = AsyncValue.error(e, st);
    }
  }
}

/// Selected jadwal provider
final selectedJadwalProvider = StateProvider<Jadwal?>((ref) => null);
