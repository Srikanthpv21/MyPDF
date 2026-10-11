import 'dart:typed_data';
import 'package:flutter/material.dart';

enum PdfSourceType {
  file,
  memory,
  asset,
  network,
}

enum DocumentCategory {
  all,
  pdf,
  word,
  excel,
  ppt,
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

  DocumentCategory get category {
    final lower = (path.isNotEmpty ? path : title).toLowerCase();
    if (lower.endsWith('.pdf')) return DocumentCategory.pdf;
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return DocumentCategory.word;
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls') || lower.endsWith('.csv')) return DocumentCategory.excel;
    if (lower.endsWith('.pptx') || lower.endsWith('.ppt')) return DocumentCategory.ppt;
    return DocumentCategory.pdf;
  }

  String get fileExtension {
    final name = path.isNotEmpty ? path : title;
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      return name.substring(dot + 1).toUpperCase();
    }
    return 'PDF';
  }

  Color get categoryColor {
    switch (category) {
      case DocumentCategory.pdf:
        return const Color(0xFFEF4444);
      case DocumentCategory.word:
        return const Color(0xFF2563EB);
      case DocumentCategory.excel:
        return const Color(0xFF16A34A);
      case DocumentCategory.ppt:
        return const Color(0xFFEA580C);
      case DocumentCategory.all:
        return const Color(0xFF6366F1);
    }
  }

  IconData get categoryIcon {
    switch (category) {
      case DocumentCategory.pdf:
        return Icons.picture_as_pdf_rounded;
      case DocumentCategory.word:
        return Icons.description_rounded;
      case DocumentCategory.excel:
        return Icons.table_chart_rounded;
      case DocumentCategory.ppt:
        return Icons.slideshow_rounded;
      case DocumentCategory.all:
        return Icons.folder_copy_rounded;
    }
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

