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
}

