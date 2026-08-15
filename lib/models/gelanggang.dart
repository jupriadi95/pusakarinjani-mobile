import 'event.dart';

/// Gelanggang model — represents an arena/ring for matches.
/// This is the central entity that connects operator, juri, and monitor.
class Gelanggang {
  final int? id;
  final String? documentId;
  final String? kodeGelanggang;
  final String? statusTanding; // standby | berlangsung | tutup
  final String? atlit1Id;
  final String? atlit2Id;
  final String? keterangan;
  final Event? event;

  const Gelanggang({
    this.id,
    this.documentId,
    this.kodeGelanggang,
    this.statusTanding,
    this.atlit1Id,
    this.atlit2Id,
    this.keterangan,
    this.event,
  });

  bool get isBerlangsung => statusTanding == 'berlangsung';
  bool get isStandby => statusTanding == 'standby' || statusTanding == null;

  factory Gelanggang.fromJson(Map<String, dynamic> json) {
    return Gelanggang(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      kodeGelanggang: json['kode_gelanggang'] as String?,
      statusTanding: json['status_tanding'] as String?,
      atlit1Id: json['atlit_1_id'] as String?,
      atlit2Id: json['atlit_2_id'] as String?,
      keterangan: json['keterangan'] as String?,
      event: json['event'] != null
          ? (json['event'] is Map<String, dynamic>
              ? Event.fromJson(json['event'] as Map<String, dynamic>)
              : null)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'kode_gelanggang': kodeGelanggang,
        'status_tanding': statusTanding,
        'atlit_1_id': atlit1Id,
        'atlit_2_id': atlit2Id,
        'keterangan': keterangan,
        'event': event?.toJson(),
      };

  Gelanggang copyWith({
    int? id,
    String? documentId,
    String? kodeGelanggang,
    String? statusTanding,
    String? atlit1Id,
    String? atlit2Id,
    String? keterangan,
    Event? event,
  }) {
    return Gelanggang(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      kodeGelanggang: kodeGelanggang ?? this.kodeGelanggang,
      statusTanding: statusTanding ?? this.statusTanding,
      atlit1Id: atlit1Id ?? this.atlit1Id,
      atlit2Id: atlit2Id ?? this.atlit2Id,
      keterangan: keterangan ?? this.keterangan,
      event: event ?? this.event,
    );
  }
}
