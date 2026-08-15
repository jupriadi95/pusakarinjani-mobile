import 'peserta.dart';

/// Nilai model — represents a score entry from a judge.
class Nilai {
  final int? id;
  final String? documentId;
  final Peserta? peserta;
  final int? jumlah;
  final String? menitKe;
  final DateTime? createdAt;

  const Nilai({
    this.id,
    this.documentId,
    this.peserta,
    this.jumlah,
    this.menitKe,
    this.createdAt,
  });

  /// Human-readable label for this score type
  String get poinLabel {
    switch (jumlah) {
      case 1:
        return 'Pukulan';
      case 2:
        return 'Tendangan';
      case 3:
        return 'Jatuhan';
      case -1:
        return 'Binaan';
      case -2:
        return 'Teguran';
      case -3:
        return 'Peringatan';
      case 4:
        return 'Jatuhan (KP)';
      default:
        return 'Poin';
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
        'createdAt': createdAt?.toIso8601String(),
      };
}
