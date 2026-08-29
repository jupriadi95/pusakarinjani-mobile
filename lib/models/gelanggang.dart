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

  factory Gelanggang.fromJson(Map<String, dynamic> rawJson) {
    final Map<String, dynamic> json = rawJson['attributes'] is Map
        ? Map<String, dynamic>.from(rawJson['attributes'] as Map)
        : rawJson;

    final idVal = rawJson['id'] as int? ?? json['id'] as int?;
    final docIdVal = (rawJson['documentId'] ?? json['documentId'])?.toString();

    final a1 = (json['atlit_1_id'] ??
            json['atlet_1_id'] ??
            json['atlit1Id'] ??
            json['atlet1Id'] ??
            rawJson['atlit_1_id'] ??
            rawJson['atlet_1_id'] ??
            rawJson['atlit1Id'] ??
            rawJson['atlet1Id'])
        ?.toString();

    final a2 = (json['atlit_2_id'] ??
            json['atlet_2_id'] ??
            json['atlit2Id'] ??
            json['atlet2Id'] ??
            rawJson['atlit_2_id'] ??
            rawJson['atlet_2_id'] ??
            rawJson['atlit2Id'] ??
            rawJson['atlet2Id'])
        ?.toString();

    final eventData = json['event'] ?? rawJson['event'];
    Event? resolvedEvent;
    if (eventData != null && eventData is Map<String, dynamic>) {
      resolvedEvent = Event.fromJson(eventData);
    } else if (eventData != null && eventData is Map) {
      resolvedEvent = Event.fromJson(Map<String, dynamic>.from(eventData));
    }

    return Gelanggang(
      id: idVal,
      documentId: docIdVal,
      kodeGelanggang: (json['kode_gelanggang'] ??
              json['kodeGelanggang'] ??
              rawJson['kode_gelanggang'] ??
              rawJson['kodeGelanggang'])
          ?.toString(),
      statusTanding: (json['status_tanding'] ??
              json['statusTanding'] ??
              rawJson['status_tanding'] ??
              rawJson['statusTanding'])
          ?.toString(),
      atlit1Id: a1,
      atlit2Id: a2,
      keterangan: (json['keterangan'] ?? rawJson['keterangan'])?.toString(),
      event: resolvedEvent,
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
