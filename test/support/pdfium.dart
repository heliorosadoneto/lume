// PDFium para os testes no Linux: usa a biblioteca baixada pelo hook do
// pdfium_dart em .dart_tool (ou PDFIUM_PATH, se definido).
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

Future<void> initPdfiumForTests() async {
  final env = Platform.environment['PDFIUM_PATH'];
  if (env == null) {
    final root = Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build');
    final lib = root.existsSync()
        ? root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('libpdfium.so')).firstOrNull
        : null;
    if (lib != null) Pdfrx.pdfiumModulePath = lib.absolute.path;
  }
  Pdfrx.cacheDirectoryPath ??= Directory.systemTemp.createTempSync('pdfrx').path;
  await pdfrxInitialize(tmpPath: Pdfrx.cacheDirectoryPath);
}
