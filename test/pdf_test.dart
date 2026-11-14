import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/epub.dart';
import 'package:lume/library.dart';
import 'package:lume/pdf.dart';
import 'package:lume/theme.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'support/pdfium.dart';

void main() {
  test('Metadados do PDF: título e autor do /Info (não do sumário)', () {
    final m = PdfMeta.read('test/fixtures/helena-amostra.pdf');
    expect(m.title, 'Helena');
    expect(m.author, 'Machado de Assis');
    expect(m.format, BookFormat.pdf);
    expect(m.isPdf, isTrue);
    expect(m.id, startsWith('pdf:'));
  });

  test('PDF sem metadados: título vem do nome do arquivo', () {
    final m = PdfMeta.read('demo_folder/pdf/sem-metadados/memorial-de-aires.pdf');
    expect(m.title, 'Memorial de Aires');
    expect(m.author, '');
    expect(PdfMeta.titleFromFile('/x/o_alienista-de_machado.pdf'), 'O Alienista de Machado');
  });

  test('Strings PDF: escapes, octal, hex UTF-16 e XMP', () {
    expect(
      PdfMeta.infoFrom('trailer << /Info 7 0 R >>\n7 0 obj << /Title (Mem\\363rias \\(1881\\)) /Author <FEFF00C9007300610075> >> endobj').title,
      'Memórias (1881)',
    );
    expect(PdfMeta.infoFrom('trailer << /Info 7 0 R >>\n7 0 obj << /Author <FEFF00C9007300610075> >> endobj').author, 'Ésau');
    expect(PdfMeta.infoFrom('<x:xmpmeta><dc:title><rdf:Alt><rdf:li xml:lang="x-default">Iracema</rdf:li></rdf:Alt></dc:title></x:xmpmeta>').title, 'Iracema');
  });

  test('Mesmo PDF com outro nome tem o mesmo identificador', () {
    final tmp = Directory.systemTemp.createTempSync('lumepdf');
    final copy = File('test/fixtures/helena-amostra.pdf').copySync(p.join(tmp.path, 'outro-nome.pdf'));
    expect(PdfMeta.idFor(copy.path), PdfMeta.idFor('test/fixtures/helena-amostra.pdf'));
    expect(PdfMeta.idFor(copy.path), isNot(PdfMeta.idFor('demo_folder/pdf/helena.pdf')));
  });

  test('Arquivo que não é PDF é recusado', () {
    final f = File(p.join(Directory.systemTemp.createTempSync('lumepdf').path, 'falso.pdf'))..writeAsStringSync('olá');
    expect(() => PdfMeta.read(f.path), throwsA(isA<EpubException>()));
    expect(Library.isBook('a/B.PDF'), isTrue);
    expect(Library.isBook('a/b.txt'), isTrue);
    expect(Library.isBook('a/b.docx'), isFalse);
  });

  test('Filtro de tema: branco é original; preto inverte o papel', () {
    expect(pdfPageFilter(PageTheme.branco), isNull);
    expect(pdfPageFilter(PageTheme.preto), isNotNull);
  });

  test('PDFium abre o PDF, conta páginas, lê o sumário e gera a capa', () async {
    await initPdfiumForTests();
    final doc = await PdfDocument.openFile('demo_folder/pdf/helena.pdf');
    expect(doc.pages.length, greaterThan(200));
    final outline = await doc.loadOutline();
    expect(outline.first.title, 'Capítulo I');
    expect(outline.first.dest?.pageNumber, 2);
    await doc.dispose();
  });
}
