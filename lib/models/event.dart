import 'media.dart';

/// Event model — represents a silat tournament/competition event.
class Event {
  final int? id;
  final String? documentId;
  final String? kodeEvent;
  final String? namaEvent;
  final String? lokasiEvent;
  final String? tanggalMulai;
  final String? biayaPendaftaran;
  final String? status; // segera | berlangsung | ditutup | selesai
  final Media? cover;

  const Event({
    this.id,
    this.documentId,
    this.kodeEvent,
    this.namaEvent,
    this.lokasiEvent,
    this.tanggalMulai,
    this.biayaPendaftaran,
    this.status,
    this.cover,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      kodeEvent: json['kode_event'] as String?,
      namaEvent: json['nama_event'] as String?,
      lokasiEvent: json['lokasi_event'] as String?,
      tanggalMulai: json['tanggal_mulai'] as String?,
      biayaPendaftaran: json['biaya_pendaftaran'] as String?,
      status: json['status'] as String?,
      cover: json['cover'] != null ? Media.fromJson(json['cover'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'kode_event': kodeEvent,
        'nama_event': namaEvent,
        'lokasi_event': lokasiEvent,
        'tanggal_mulai': tanggalMulai,
        'biaya_pendaftaran': biayaPendaftaran,
        'status': status,
        'cover': cover?.toJson(),
      };
}
