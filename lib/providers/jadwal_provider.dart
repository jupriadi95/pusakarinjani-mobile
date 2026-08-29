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
      final targetKode = (gelanggang.kodeGelanggang ?? '').toLowerCase().trim();

      debugPrint(
          '[JadwalProvider] Fetching jadwal for gelanggang: docId=$targetDocId, id=$targetId, kode=$targetKode');

      // ── Strategy 1: Filter langsung via Strapi REST berdasarkan documentId gelanggang ──
      List<Jadwal> arenaMatches = [];

      if (targetDocId.isNotEmpty) {
        final resp1 = await _api.findProtect('jadwals', params: {
          'populate': '*',
          'pagination[pageSize]': '200',
          'sort[0]': 'nomor_partai:asc',
          'filters[gelanggang][documentId][\$eq]': targetDocId,
        });
        final data1 = resp1['data'] as List? ?? [];
        arenaMatches =
            data1.map((e) => Jadwal.fromJson(e as Map<String, dynamic>)).toList();
        debugPrint(
            '[JadwalProvider] Strategy 1 (docId filter): ${arenaMatches.length} matches');
      }

      // ── Strategy 2: Filter berdasarkan id gelanggang ──
      if (arenaMatches.isEmpty && targetId.isNotEmpty) {
        final resp2 = await _api.findProtect('jadwals', params: {
          'populate': '*',
          'pagination[pageSize]': '200',
          'sort[0]': 'nomor_partai:asc',
          'filters[gelanggang][id][\$eq]': targetId,
        });
        final data2 = resp2['data'] as List? ?? [];
        arenaMatches =
            data2.map((e) => Jadwal.fromJson(e as Map<String, dynamic>)).toList();
        debugPrint(
            '[JadwalProvider] Strategy 2 (id filter): ${arenaMatches.length} matches');
      }

      // ── Strategy 3: Fetch all + filter lokal berdasarkan relasi gelanggang yang terpopulasi ──
      if (arenaMatches.isEmpty) {
        final resp3 = await _api.findProtect('jadwals', params: {
          'populate': '*',
          'pagination[pageSize]': '200',
          'sort[0]': 'nomor_partai:asc',
        });
        final data3 = resp3['data'] as List? ?? [];
        final allJadwals = data3
            .map((e) => Jadwal.fromJson(e as Map<String, dynamic>))
            .toList();

        debugPrint(
            '[JadwalProvider] Strategy 3 all fetch: ${allJadwals.length} total');

        // Filter berdasarkan relasi gelanggang di dalam jadwal
        arenaMatches = allJadwals.where((j) {
          final g = j.gelanggang;
          if (g == null) return false;

          final gDocId = g.documentId ?? '';
          final gId = g.id?.toString() ?? '';
          final gKode = (g.kodeGelanggang ?? '').toLowerCase().trim();

          if (targetDocId.isNotEmpty &&
              gDocId.isNotEmpty &&
              gDocId == targetDocId) { return true; }
          if (targetId.isNotEmpty && gId.isNotEmpty && gId == targetId) {
            return true;
          }
          if (targetKode.isNotEmpty &&
              gKode.isNotEmpty &&
              gKode == targetKode) { return true; }

          return false;
        }).toList();

        debugPrint(
            '[JadwalProvider] Strategy 3 (local filter): ${arenaMatches.length} matches');
      }

      // Sort by nomor_partai ascending
      arenaMatches.sort((a, b) {
        final aNum = int.tryParse(a.nomorPartai?.toString() ?? '0') ?? 0;
        final bNum = int.tryParse(b.nomorPartai?.toString() ?? '0') ?? 0;
        return aNum.compareTo(bNum);
      });

      debugPrint(
          '[JadwalProvider] Final arena matches: ${arenaMatches.length}');
      state = AsyncValue.data(arenaMatches);
    } catch (e, st) {
      debugPrint('Error fetching operator jadwal: $e');
      state = AsyncValue.error(e, st);
    }
  }
}

/// Selected jadwal provider
final selectedJadwalProvider = StateProvider<Jadwal?>((ref) => null);
