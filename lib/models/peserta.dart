import 'media.dart';

/// Peserta model — represents a participant/athlete.
class Peserta {
  final int? id;
  final String? documentId;
  final String? namaLengkap;
  final String? tempatLahir;
  final String? tanggalLahir;
  final String? jenisKelamin;
  final String? kontingen;
  final String? perguruan;
  final double? berat;
  final double? tinggi;
  final String? whatsapp;
  final Media? pasFoto;
  final Media? actionFoto;

  const Peserta({
    this.id,
    this.documentId,
    this.namaLengkap,
    this.tempatLahir,
    this.tanggalLahir,
    this.jenisKelamin,
    this.kontingen,
    this.perguruan,
    this.berat,
    this.tinggi,
    this.whatsapp,
    this.pasFoto,
    this.actionFoto,
  });

  /// Get initials (first 2 characters) for avatar display
  String get initials {
    if (namaLengkap == null || namaLengkap!.isEmpty) return '??';
    return namaLengkap!.substring(0, namaLengkap!.length >= 2 ? 2 : 1).toUpperCase();
  }

  factory Peserta.fromJson(Map<String, dynamic> json) {
    return Peserta(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      namaLengkap: json['nama_lengkap'] as String?,
      tempatLahir: json['tempat_lahir'] as String?,
      tanggalLahir: json['tanggal_lahir'] as String?,
      jenisKelamin: json['jenis_kelamin'] as String?,
      kontingen: json['kontingen'] as String?,
      perguruan: json['perguruan'] as String?,
      berat: (json['berat'] as num?)?.toDouble(),
      tinggi: (json['tinggi'] as num?)?.toDouble(),
      whatsapp: json['whatsapp'] as String?,
      pasFoto: json['pas_foto'] != null
          ? Media.fromJson(json['pas_foto'] as Map<String, dynamic>)
          : null,
      actionFoto: json['action_foto'] != null
          ? Media.fromJson(json['action_foto'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'nama_lengkap': namaLengkap,
        'tempat_lahir': tempatLahir,
        'tanggal_lahir': tanggalLahir,
        'jenis_kelamin': jenisKelamin,
        'kontingen': kontingen,
        'perguruan': perguruan,
        'berat': berat,
        'tinggi': tinggi,
        'whatsapp': whatsapp,
        'pas_foto': pasFoto?.toJson(),
        'action_foto': actionFoto?.toJson(),
      };
}
