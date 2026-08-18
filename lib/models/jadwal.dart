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

  // ── KP Discipline & State Tracking ──
  final int kpBinaanMerah;
  final int kpTeguranMerah;
  final int kpPembinaanMerah;
  final String kpStatusMerah; // 'normal' | 'diskualifikasi'

  final int kpBinaanBiru;
  final int kpTeguranBiru;
  final int kpPembinaanBiru;
  final String kpStatusBiru; // 'normal' | 'diskualifikasi'

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
    this.kpBinaanMerah = 0,
    this.kpTeguranMerah = 0,
    this.kpPembinaanMerah = 0,
    this.kpStatusMerah = 'normal',
    this.kpBinaanBiru = 0,
    this.kpTeguranBiru = 0,
    this.kpPembinaanBiru = 0,
    this.kpStatusBiru = 'normal',
  });

  /// Get merah athlete, handling multiple possible field names
  Peserta? get merahPeserta => atlitMerah;

  /// Get biru athlete, handling multiple possible field names
  Peserta? get biruPeserta => atlitBiru;

  factory Jadwal.fromJson(Map<String, dynamic> json) {
    // Handle multiple field name conventions for athletes
    final merah = json['atlit_merah'] ??
        json['atlet_merah'] ??
        json['peserta_merah'] ??
        json['peserta_1'] ??
        json['atlit_1'] ??
        json['atlet_1'] ??
        json['sudut_merah'];

    final biru = json['atlit_biru'] ??
        json['atlet_biru'] ??
        json['peserta_biru'] ??
        json['peserta_2'] ??
        json['atlit_2'] ??
        json['atlet_2'] ??
        json['sudut_biru'];

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
      kpBinaanMerah: json['kp_binaan_merah'] as int? ?? 0,
      kpTeguranMerah: json['kp_teguran_merah'] as int? ?? 0,
      kpPembinaanMerah: json['kp_pembinaan_merah'] as int? ?? 0,
      kpStatusMerah: json['kp_status_merah'] as String? ?? 'normal',
      kpBinaanBiru: json['kp_binaan_biru'] as int? ?? 0,
      kpTeguranBiru: json['kp_teguran_biru'] as int? ?? 0,
      kpPembinaanBiru: json['kp_pembinaan_biru'] as int? ?? 0,
      kpStatusBiru: json['kp_status_biru'] as String? ?? 'normal',
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
        'kp_binaan_merah': kpBinaanMerah,
        'kp_teguran_merah': kpTeguranMerah,
        'kp_pembinaan_merah': kpPembinaanMerah,
        'kp_status_merah': kpStatusMerah,
        'kp_binaan_biru': kpBinaanBiru,
        'kp_teguran_biru': kpTeguranBiru,
        'kp_pembinaan_biru': kpPembinaanBiru,
        'kp_status_biru': kpStatusBiru,
      };

  Jadwal copyWith({
    int? id,
    String? documentId,
    dynamic nomorPartai,
    String? babak,
    String? jenisKelamin,
    String? status,
    String? statusTanding,
    int? skorMerah,
    int? skorBiru,
    String? keterangan,
    dynamic ronde,
    Event? event,
    Gelanggang? gelanggang,
    Kelas? kelas,
    Peserta? atlitMerah,
    Peserta? atlitBiru,
    Peserta? pemenang,
    int? kpBinaanMerah,
    int? kpTeguranMerah,
    int? kpPembinaanMerah,
    String? kpStatusMerah,
    int? kpBinaanBiru,
    int? kpTeguranBiru,
    int? kpPembinaanBiru,
    String? kpStatusBiru,
  }) {
    return Jadwal(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      nomorPartai: nomorPartai ?? this.nomorPartai,
      babak: babak ?? this.babak,
      jenisKelamin: jenisKelamin ?? this.jenisKelamin,
      status: status ?? this.status,
      statusTanding: statusTanding ?? this.statusTanding,
      skorMerah: skorMerah ?? this.skorMerah,
      skorBiru: skorBiru ?? this.skorBiru,
      keterangan: keterangan ?? this.keterangan,
      ronde: ronde ?? this.ronde,
      event: event ?? this.event,
      gelanggang: gelanggang ?? this.gelanggang,
      kelas: kelas ?? this.kelas,
      atlitMerah: atlitMerah ?? this.atlitMerah,
      atlitBiru: atlitBiru ?? this.atlitBiru,
      pemenang: pemenang ?? this.pemenang,
      kpBinaanMerah: kpBinaanMerah ?? this.kpBinaanMerah,
      kpTeguranMerah: kpTeguranMerah ?? this.kpTeguranMerah,
      kpPembinaanMerah: kpPembinaanMerah ?? this.kpPembinaanMerah,
      kpStatusMerah: kpStatusMerah ?? this.kpStatusMerah,
      kpBinaanBiru: kpBinaanBiru ?? this.kpBinaanBiru,
      kpTeguranBiru: kpTeguranBiru ?? this.kpTeguranBiru,
      kpPembinaanBiru: kpPembinaanBiru ?? this.kpPembinaanBiru,
      kpStatusBiru: kpStatusBiru ?? this.kpStatusBiru,
    );
  }
}
