import 'media.dart';

/// Sponsor model — represents an event sponsor with logo and level.
/// Levels: platinum | gold | silver | bronze
class Sponsor {
  final int? id;
  final String? documentId;
  final String? label;
  final String? level; // platinum | gold | silver | bronze
  final Media? logo;

  const Sponsor({
    this.id,
    this.documentId,
    this.label,
    this.level,
    this.logo,
  });

  factory Sponsor.fromJson(Map<String, dynamic> rawJson) {
    final Map<String, dynamic> json =
        rawJson['attributes'] is Map
            ? Map<String, dynamic>.from(rawJson['attributes'] as Map)
            : rawJson;

    final idVal = rawJson['id'] as int? ?? json['id'] as int?;
    final docIdVal = (rawJson['documentId'] ?? json['documentId'])?.toString();

    final logoData = json['logo'] ?? rawJson['logo'];
    Media? resolvedLogo;
    if (logoData != null) {
      if (logoData is Map<String, dynamic>) {
        // Could be { data: { ... } } (Strapi v4) or direct media object
        final inner = logoData['data'];
        if (inner != null && inner is Map<String, dynamic>) {
          resolvedLogo = Media.fromJson(inner);
        } else {
          resolvedLogo = Media.fromJson(logoData);
        }
      }
    }

    return Sponsor(
      id: idVal,
      documentId: docIdVal,
      label: (json['label'] ?? rawJson['label'])?.toString(),
      level: (json['level'] ?? rawJson['level'])?.toString(),
      logo: resolvedLogo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'label': label,
        'level': level,
        'logo': logo?.toJson(),
      };
}
