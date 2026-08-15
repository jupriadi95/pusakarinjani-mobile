/// Media model — represents uploaded file/image from Strapi.
class Media {
  final int? id;
  final String? documentId;
  final String? name;
  final String? url;
  final String? mime;
  final double? width;
  final double? height;

  const Media({this.id, this.documentId, this.name, this.url, this.mime, this.width, this.height});

  factory Media.fromJson(Map<String, dynamic> json) {
    return Media(
      id: json['id'] as int?,
      documentId: json['documentId'] as String?,
      name: json['name'] as String?,
      url: json['url'] as String?,
      mime: json['mime'] as String?,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'name': name,
        'url': url,
        'mime': mime,
        'width': width,
        'height': height,
      };
}
