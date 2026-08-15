/// Kelas model — represents a weight/competition class.
class Kelas {
  final int? id;
  final String? documentId;
  final String? namaKelas;
  final double? beratMin;
  final double? beratMax;
  final String? keterangan;

  const Kelas({
    this.id,
    this.documentId,
    this.namaKelas,
    this.beratMin,
    this.beratMax,
    this.keterangan,
  });

  factory Kelas.fromJson(Map<String, dynamic> json) {
    return Kelas(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      namaKelas: json['nama_kelas'] as String?,
      beratMin: (json['berat_min'] as num?)?.toDouble(),
      beratMax: (json['berat_max'] as num?)?.toDouble(),
      keterangan: json['keterangan'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'nama_kelas': namaKelas,
        'berat_min': beratMin,
        'berat_max': beratMax,
        'keterangan': keterangan,
      };
}
