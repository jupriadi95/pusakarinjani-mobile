import 'peserta.dart';

/// Nilai model — represents a score entry from a judge or KP action.
class Nilai {
  final int? id;
  final String? documentId;
  final Peserta? peserta;
  final int? jumlah;
  final String? menitKe;
  final String?
  jenis; // 'pukulan' | 'tendangan' | 'jatuhan' | 'batal_jatuhan' | 'binaan' | 'teguran' | 'pembinaan' | 'diskualifikasi'
  final String? status; // 'sah' | 'ditolak' | 'buffered'
  final String? sudut; // 'merah' | 'biru'
  final String? juriId; // 'juri_1' | 'juri_2' | 'juri_3' | 'kp'
  final int? juriCount; // 1 | 2 | 3
  final String? babak; // '1' | '2' | '3'
  final String? jadwalDocId;
  final String? jadwalId;
  final DateTime? createdAt;

  const Nilai({
    this.id,
    this.documentId,
    this.peserta,
    this.jumlah,
    this.menitKe,
    this.jenis,
    this.status,
    this.sudut,
    this.juriId,
    this.juriCount,
    this.babak,
    this.jadwalDocId,
    this.jadwalId,
    this.createdAt,
  });

  /// Check if this score is approved/valid (sah)
  bool get isSah => status == null || status == 'sah';

  /// Check if this score was rejected (ditolak)
  bool get isDitolak => status == 'ditolak';

  /// Human-readable label for this score type
  String get poinLabel {
    if (jenis != null) {
      switch (jenis!.toLowerCase()) {
        case 'pukulan':
          return 'Pukulan (+1)';
        case 'tendangan':
          return 'Tendangan (+2)';
        case 'jatuhan':
          return (jumlah != null && jumlah! < 0)
              ? 'Batal Jatuhan ($jumlah)'
              : 'Jatuhan (+3)';
        case 'batal_jatuhan':
          return 'Batal Jatuhan (-3)';
        case 'binaan':
          return 'Binaan (0)';
        case 'batal_binaan':
          return 'Binaan Dibatalkan (0)';
        case 'teguran':
          return (jumlah != null && jumlah! > 0)
              ? 'Pelanggaran Dibatalkan (+$jumlah)'
              : (jumlah == -2 ? 'Teguran 2 (-2)' : 'Teguran 1 (-1)');
        case 'batal_teguran':
          return 'Pelanggaran Dibatalkan (+${jumlah ?? 1})';
        case 'pembinaan':
          return (jumlah != null && jumlah! > 0)
              ? 'Pelanggaran Dibatalkan (+$jumlah)'
              : (jumlah == -10 ? 'Peringatan 2 (-10)' : 'Peringatan 1 (-5)');
        case 'batal_pembinaan':
          return 'Pelanggaran Dibatalkan (+${jumlah ?? 5})';
        case 'diskualifikasi':
          return 'Diskualifikasi';
        case 'reset_babak':
          return 'Reset Babak';
      }
    }

    switch (jumlah) {
      case 1:
        return 'Pukulan (+1)';
      case 2:
        return 'Tendangan (+2)';
      case 3:
        return 'Jatuhan (+3)';
      case -3:
        return 'Batal Jatuhan (-3)';
      case -1:
        return 'Teguran (-1)';
      case -2:
        return 'Teguran 2 (-2)';
      case -5:
        return 'Peringatan 1 (-5)';
      case -10:
        return 'Peringatan 2 (-10)';
      default:
        return 'Poin (${jumlah != null && jumlah! > 0 ? "+$jumlah" : "$jumlah"})';
    }
  }

  factory Nilai.fromJson(Map<String, dynamic> rawJson) {
    // If wrapped in attributes (Strapi v4 format)
    final Map<String, dynamic> json = rawJson['attributes'] is Map
        ? Map<String, dynamic>.from(rawJson['attributes'] as Map)
        : rawJson;

    final idVal = rawJson['id'] as int? ?? json['id'] as int?;
    final docIdVal = (rawJson['documentId'] ?? json['documentId']) as String?;

    Peserta? resolvedPeserta;
    final pesertaData = json['peserta'] ?? rawJson['peserta'];
    if (pesertaData != null) {
      if (pesertaData is Map<String, dynamic>) {
        resolvedPeserta = Peserta.fromJson(pesertaData);
      } else if (pesertaData is Map) {
        resolvedPeserta = Peserta.fromJson(
          Map<String, dynamic>.from(pesertaData),
        );
      } else if (pesertaData is String || pesertaData is int) {
        final idStr = pesertaData.toString();
        resolvedPeserta = Peserta(id: int.tryParse(idStr), documentId: idStr);
      }
    } else if (json['atlet_id'] != null ||
        json['atletId'] != null ||
        json['peserta_id'] != null ||
        rawJson['atlet_id'] != null ||
        rawJson['atletId'] != null ||
        rawJson['peserta_id'] != null) {
      final idStr = (json['atlet_id'] ??
              json['atletId'] ??
              json['peserta_id'] ??
              rawJson['atlet_id'] ??
              rawJson['atletId'] ??
              rawJson['peserta_id'])
          .toString();
      resolvedPeserta = Peserta(id: int.tryParse(idStr), documentId: idStr);
    }

    // Extract babak: can be string, int, or inside jadwal/json
    String? resolvedBabak = (json['babak'] ?? rawJson['babak'])?.toString();
    if (resolvedBabak == null ||
        resolvedBabak.isEmpty ||
        resolvedBabak == 'null') {
      if (json['jadwal'] is Map && (json['jadwal'] as Map)['babak'] != null) {
        resolvedBabak = (json['jadwal'] as Map)['babak'].toString();
      }
    }

    // Extract jadwal reference
    String? resolvedJadwalDocId = (json['jadwal_doc_id'] ??
            json['jadwalDocId'] ??
            rawJson['jadwal_doc_id'] ??
            rawJson['jadwalDocId'])
        ?.toString();
    String? resolvedJadwalId = (json['jadwal_id'] ??
            json['jadwalId'] ??
            rawJson['jadwal_id'] ??
            rawJson['jadwalId'])
        ?.toString();
    final jadwalData = json['jadwal'] ?? rawJson['jadwal'];
    if (jadwalData != null) {
      if (jadwalData is Map) {
        resolvedJadwalDocId ??=
            (jadwalData['documentId'] ?? jadwalData['docId'])?.toString();
        resolvedJadwalId ??= (jadwalData['id'])?.toString();
      } else if (jadwalData is String || jadwalData is int) {
        final jStr = jadwalData.toString();
        if (int.tryParse(jStr) != null) {
          resolvedJadwalId ??= jStr;
        } else {
          resolvedJadwalDocId ??= jStr;
        }
      }
    }

    return Nilai(
      id: idVal,
      documentId: docIdVal,
      peserta: resolvedPeserta,
      jumlah: (json['jumlah'] ?? rawJson['jumlah']) as int?,
      menitKe: (json['menit_ke'] ??
          json['menitKe'] ??
          rawJson['menit_ke'] ??
          rawJson['menitKe']) as String?,
      jenis: (json['jenis'] ?? rawJson['jenis']) as String?,
      status: (json['status'] ?? rawJson['status']) as String?,
      sudut: (json['sudut'] ?? rawJson['sudut']) as String?,
      juriId: (json['juri_id'] ??
          json['juriId'] ??
          rawJson['juri_id'] ??
          rawJson['juriId']) as String?,
      juriCount: (json['juri_count'] ??
          json['juriCount'] ??
          rawJson['juri_count'] ??
          rawJson['juriCount']) as int?,
      babak: (resolvedBabak != null &&
              resolvedBabak != 'null' &&
              resolvedBabak.isNotEmpty)
          ? resolvedBabak
          : null,
      jadwalDocId: resolvedJadwalDocId,
      jadwalId: resolvedJadwalId,
      createdAt: (json['createdAt'] ?? rawJson['createdAt']) != null
          ? DateTime.tryParse(
              (json['createdAt'] ?? rawJson['createdAt']) as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'documentId': documentId,
    'peserta': peserta?.toJson(),
    'jumlah': jumlah,
    'menit_ke': menitKe,
    'jenis': jenis,
    'status': status,
    'sudut': sudut,
    'juri_id': juriId,
    'juri_count': juriCount,
    'babak': babak,
    'jadwalDocId': jadwalDocId,
    'jadwalId': jadwalId,
    'createdAt': createdAt?.toIso8601String(),
  };

  Nilai copyWith({
    int? id,
    String? documentId,
    Peserta? peserta,
    int? jumlah,
    String? menitKe,
    String? jenis,
    String? status,
    String? sudut,
    String? juriId,
    int? juriCount,
    String? babak,
    String? jadwalDocId,
    String? jadwalId,
    DateTime? createdAt,
  }) {
    return Nilai(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      peserta: peserta ?? this.peserta,
      jumlah: jumlah ?? this.jumlah,
      menitKe: menitKe ?? this.menitKe,
      jenis: jenis ?? this.jenis,
      status: status ?? this.status,
      sudut: sudut ?? this.sudut,
      juriId: juriId ?? this.juriId,
      juriCount: juriCount ?? this.juriCount,
      babak: babak ?? this.babak,
      jadwalDocId: jadwalDocId ?? this.jadwalDocId,
      jadwalId: jadwalId ?? this.jadwalId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
