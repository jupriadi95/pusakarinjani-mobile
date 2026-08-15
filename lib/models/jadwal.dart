import 'event.dart';
import 'gelanggang.dart';
import 'kelas.dart';
import 'peserta.dart';

/// Jadwal model — represents a match schedule entry.
class Jadwal {
  final int? id;
  final String? documentId;
  final dynamic nomorPartai;
  final String? babak;
  final String? jenisKelamin;
  final String? status;
  final String? statusTanding;
  final int? skorMerah;
  final int? skorBiru;
  final String? keterangan;
  final dynamic ronde;
  final Event? event;
  final Gelanggang? gelanggang;
  final Kelas? kelas;
  final Peserta? atlitMerah;
  final Peserta? atlitBiru;
  final Peserta? pemenang;

  const Jadwal({
    this.id,
    this.documentId,
    this.nomorPartai,
    this.babak,
    this.jenisKelamin,
    this.status,
    this.statusTanding,
    this.skorMerah,
    this.skorBiru,
    this.keterangan,
    this.ronde,
    this.event,
    this.gelanggang,
    this.kelas,
    this.atlitMerah,
    this.atlitBiru,
    this.pemenang,
  });

  /// Get merah athlete, handling multiple possible field names
  Peserta? get merahPeserta => atlitMerah;

  /// Get biru athlete, handling multiple possible field names
  Peserta? get biruPeserta => atlitBiru;

  factory Jadwal.fromJson(Map<String, dynamic> json) {
    // Handle multiple field name conventions for athletes
    final merah = json['atlit_merah'] ?? json['peserta_1'] ?? json['atlit_1'];
    final biru = json['atlit_biru'] ?? json['peserta_2'] ?? json['atlit_2'];

    return Jadwal(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      nomorPartai: json['nomor_partai'],
      babak: json['babak'] as String?,
      jenisKelamin: json['jenis_kelamin'] as String?,
      status: json['status'] as String?,
      statusTanding: json['status_tanding'] as String?,
      skorMerah: json['skor_merah'] as int?,
      skorBiru: json['skor_biru'] as int?,
      keterangan: json['keterangan'] as String?,
      ronde: json['ronde'],
      event: json['event'] != null && json['event'] is Map<String, dynamic>
          ? Event.fromJson(json['event'] as Map<String, dynamic>)
          : null,
      gelanggang: json['gelanggang'] != null && json['gelanggang'] is Map<String, dynamic>
          ? Gelanggang.fromJson(json['gelanggang'] as Map<String, dynamic>)
          : null,
      kelas: json['kelas'] != null && json['kelas'] is Map<String, dynamic>
          ? Kelas.fromJson(json['kelas'] as Map<String, dynamic>)
          : null,
      atlitMerah: merah != null && merah is Map<String, dynamic>
          ? Peserta.fromJson(merah)
          : null,
      atlitBiru: biru != null && biru is Map<String, dynamic>
          ? Peserta.fromJson(biru)
          : null,
      pemenang: json['pemenang'] != null && json['pemenang'] is Map<String, dynamic>
          ? Peserta.fromJson(json['pemenang'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'nomor_partai': nomorPartai,
        'babak': babak,
        'jenis_kelamin': jenisKelamin,
        'status': status,
        'status_tanding': statusTanding,
        'skor_merah': skorMerah,
        'skor_biru': skorBiru,
        'keterangan': keterangan,
        'ronde': ronde,
        'event': event?.toJson(),
        'gelanggang': gelanggang?.toJson(),
        'kelas': kelas?.toJson(),
        'atlit_merah': atlitMerah?.toJson(),
        'atlit_biru': atlitBiru?.toJson(),
        'pemenang': pemenang?.toJson(),
      };
}
