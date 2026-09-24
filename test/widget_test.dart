import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer/models/pdf_document_item.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PdfDocumentItem creation is valid', () {
    final item = PdfDocumentItem(
      id: 'test_doc',
      title: 'Sample Document.pdf',
      subtitle: 'Downloads | 120 KB',
      type: PdfSourceType.file,
      path: '/storage/emulated/0/Download/Sample.pdf',
    );
    expect(item.id, equals('test_doc'));
    expect(item.title, contains('Sample Document.pdf'));
    expect(item.type, equals(PdfSourceType.file));
  });

  test('PdfDocumentItem copyWith works accurately', () {
    final original = PdfDocumentItem(
      id: 'doc1',
      title: 'Original.pdf',
      subtitle: 'Documents | 50 KB',
      type: PdfSourceType.file,
      path: '/storage/Original.pdf',
    );
    final renamed = original.copyWith(
      title: 'Renamed.pdf',
      path: '/storage/Renamed.pdf',
    );
    expect(renamed.id, equals('doc1'));
    expect(renamed.title, equals('Renamed.pdf'));
    expect(renamed.path, equals('/storage/Renamed.pdf'));
    expect(renamed.subtitle, equals('Documents | 50 KB'));
  });
}
