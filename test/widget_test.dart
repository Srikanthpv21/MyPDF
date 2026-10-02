import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_viewer/models/pdf_document_item.dart';
import 'package:pdf_viewer/widgets/search_bar_overlay.dart';
import 'package:pdf_viewer/widgets/page_thumbnail_sheet.dart';

class FastMomentumScrollPhysics extends BouncingScrollPhysics {
  const FastMomentumScrollPhysics({super.parent, super.decelerationRate});

  @override
  FastMomentumScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastMomentumScrollPhysics(
      parent: buildParent(ancestor),
      decelerationRate: decelerationRate,
    );
  }

  @override
  double get dragStartDistanceMotionThreshold => 3.5;

  @override
  double get minFlingVelocity => 40.0;

  @override
  double get maxFlingVelocity => 14000.0;

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    if (velocity.abs() < tolerance.velocity) {
      return null;
    }
    return super.createBallisticSimulation(position, velocity * 1.35);
  }
}

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

  test('PdfDocumentItem correctly identifies Word, Excel, PPT, and PDF categories', () {
    final pdfDoc = PdfDocumentItem(
      id: '1',
      title: 'Report.pdf',
      subtitle: 'Downloads',
      type: PdfSourceType.file,
      path: '/path/Report.pdf',
    );
    expect(pdfDoc.category, equals(DocumentCategory.pdf));
    expect(pdfDoc.fileExtension, equals('PDF'));

    final wordDoc = PdfDocumentItem(
      id: '2',
      title: 'Resume.docx',
      subtitle: 'Documents',
      type: PdfSourceType.file,
      path: '/path/Resume.docx',
    );
    expect(wordDoc.category, equals(DocumentCategory.word));
    expect(wordDoc.fileExtension, equals('DOCX'));

    final excelDoc = PdfDocumentItem(
      id: '3',
      title: 'Budget.xlsx',
      subtitle: 'Downloads',
      type: PdfSourceType.file,
      path: '/path/Budget.xlsx',
    );
    expect(excelDoc.category, equals(DocumentCategory.excel));
    expect(excelDoc.fileExtension, equals('XLSX'));

    final pptDoc = PdfDocumentItem(
      id: '4',
      title: 'Slides.pptx',
      subtitle: 'Documents',
      type: PdfSourceType.file,
      path: '/path/Slides.pptx',
    );
    expect(pptDoc.category, equals(DocumentCategory.ppt));
    expect(pptDoc.fileExtension, equals('PPTX'));
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

  test('ClampingScrollSimulation test', () {
    final sim = ClampingScrollSimulation(
      position: 0.0,
      velocity: 500.0,
      friction: 0.0075,
    );
    expect(sim.dx(0.0), isNotNull);
  });

  test('FastMomentumScrollPhysics test', () {
    const physics = FastMomentumScrollPhysics();
    expect(physics.dragStartDistanceMotionThreshold, equals(3.5));
    expect(physics.minFlingVelocity, equals(40.0));
    expect(physics.maxFlingVelocity, equals(14000.0));
  });

  testWidgets('SliverPrototypeExtentList with BouncingScrollPhysics and RefreshIndicator builds properly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {},
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverPrototypeExtentList(
                  prototypeItem: const SizedBox(height: 78),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const SizedBox(height: 78),
                    childCount: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  test('PdfDocumentItem matchesQuery and serialization tests', () {
    final doc = PdfDocumentItem(
      id: 'doc_101',
      title: 'Annual Report 2026.pdf',
      subtitle: 'Downloads | 4.5 MB',
      type: PdfSourceType.file,
      path: '/storage/emulated/0/Download/Annual Report 2026.pdf',
      pageCount: 35,
    );

    expect(doc.matchesQuery('annual'), isTrue);
    expect(doc.matchesQuery('REPORT'), isTrue);
    expect(doc.matchesQuery('downloads'), isTrue);
    expect(doc.matchesQuery('nonexistent_keyword'), isFalse);

    final json = doc.toJson();
    final reconstructed = PdfDocumentItem.fromJson(json);
    expect(reconstructed.id, equals('doc_101'));
    expect(reconstructed.title, equals('Annual Report 2026.pdf'));
    expect(reconstructed.pageCount, equals(35));
  });

  testWidgets('SearchBarOverlay displays matches and navigation triggers properly', (tester) async {
    final controller = TextEditingController(text: 'flutter');
    int nextClicks = 0;
    int prevClicks = 0;
    bool closed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchBarOverlay(
            controller: controller,
            currentMatchIndex: 3,
            totalMatches: 12,
            isSearching: false,
            onSearchSubmitted: (_) {},
            onNextMatch: () => nextClicks++,
            onPreviousMatch: () => prevClicks++,
            onClose: () => closed = true,
          ),
        ),
      ),
    );

    expect(find.text('3 / 12'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pump();
    expect(nextClicks, equals(1));

    await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
    await tester.pump();
    expect(prevClicks, equals(1));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('PageThumbnailSheet renders page count and selection accurately', (tester) async {
    int selectedPage = -1;
    int toggledBookmark = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageThumbnailSheet(
            currentPage: 2,
            totalPages: 5,
            bookmarkedPages: const {2, 4},
            onPageSelected: (p) => selectedPage = p,
            onBookmarkToggled: (p) => toggledBookmark = p,
          ),
        ),
      ),
    );

    expect(find.text('Pages & Thumbnails'), findsOneWidget);
    expect(find.text('Saved (2)'), findsOneWidget);
    expect(find.text('P. 1'), findsOneWidget);
    expect(find.text('P. 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark_border_rounded).first);
    await tester.pump();
    expect(toggledBookmark, isPositive);

    await tester.tap(find.text('P. 1'));
    await tester.pump();
    expect(selectedPage, equals(1));
  });
}
