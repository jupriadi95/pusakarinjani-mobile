import 'peserta.dart';

/// Nilai model — represents a score entry from a judge or KP action.
class Nilai {
  final int? id;
  final String? documentId;
  final Peserta? peserta;
  final int? jumlah;
  final String? menitKe;
  final String? jenis; // 'pukulan' | 'tendangan' | 'jatuhan' | 'batal_jatuhan' | 'binaan' | 'teguran' | 'pembinaan' | 'diskualifikasi'
  final String? status; // 'sah' | 'ditolak' | 'buffered'
  final String? sudut; // 'merah' | 'biru'
  final String? juriId; // 'juri_1' | 'juri_2' | 'juri_3' | 'kp'
  final int? juriCount; // 1 | 2 | 3
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
          return 'Jatuhan (+3)';
        case 'batal_jatuhan':
          return 'Batal Jatuhan (-3)';
        case 'binaan':
          return 'Binaan (0)';
        case 'teguran':
          return jumlah == -2 ? 'Teguran 2 (-2)' : 'Teguran 1 (-1)';
        case 'pembinaan':
          return jumlah == -10 ? 'Peringatan 2 (-10)' : 'Peringatan 1 (-5)';
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

  factory Nilai.fromJson(Map<String, dynamic> json) {
    return Nilai(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      peserta: json['peserta'] != null
          ? (json['peserta'] is Map<String, dynamic>
              ? Peserta.fromJson(json['peserta'] as Map<String, dynamic>)
              : null)
          : null,
      jumlah: json['jumlah'] as int?,
      menitKe: json['menit_ke'] as String?,
      jenis: json['jenis'] as String?,
      status: json['status'] as String?,
      sudut: json['sudut'] as String?,
      juriId: json['juri_id'] as String?,
      juriCount: json['juri_count'] as int?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
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
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
