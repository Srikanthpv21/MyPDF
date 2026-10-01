import 'dart:typed_data';

enum PdfSourceType {
  file,
  memory,
  asset,
  network,
}

class PdfDocumentItem {
  final String id;
  final String title;
  final String subtitle;
  final PdfSourceType type;
  final String path;
  final Uint8List? bytes;
  final String? fileSize;
  final DateTime? lastModified;
  int pageCount;

  late final String _searchKey = '$title $subtitle $path'.toLowerCase();

  bool matchesQuery(String query) {
    if (query.isEmpty) return true;
    return _searchKey.contains(query.toLowerCase());
  }

  PdfDocumentItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    this.path = '',
    this.bytes,
    this.fileSize,
    this.lastModified,
    this.pageCount = 0,
  });

  PdfDocumentItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    PdfSourceType? type,
    String? path,
    Uint8List? bytes,
    String? fileSize,
    DateTime? lastModified,
    int? pageCount,
  }) {
    return PdfDocumentItem(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      fileSize: fileSize ?? this.fileSize,
      lastModified: lastModified ?? this.lastModified,
      pageCount: pageCount ?? this.pageCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'type': type.index,
      'path': path,
      'fileSize': fileSize,
      'lastModified': lastModified?.toIso8601String(),
      'pageCount': pageCount,
    };
  }

  factory PdfDocumentItem.fromJson(Map<String, dynamic> json) {
    return PdfDocumentItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      type: PdfSourceType.values[(json['type'] as int? ?? 0).clamp(0, PdfSourceType.values.length - 1)],
      path: json['path'] as String? ?? '',
      fileSize: json['fileSize'] as String?,
      lastModified: json['lastModified'] != null ? DateTime.tryParse(json['lastModified'] as String) : null,
      pageCount: json['pageCount'] as int? ?? 0,
    );
  }
}

