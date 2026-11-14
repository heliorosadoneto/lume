// Importar livros para a pasta do Lume: copia em blocos (com progresso),
// renomeia em caso de nome repetido ("livro (2).pdf") e pula arquivos que já
// estão na pasta com o mesmo conteúdo (comparação por SHA-1).
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Formatos que o Lume abre.
const bookExtensions = ['epub', 'pdf', 'txt', 'md', 'markdown'];

bool isBookPath(String path) => bookExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''));

enum ImportOutcome { added, duplicate, unsupported, failed }

class ImportItem {
  ImportItem(this.source, this.outcome, {this.dest, this.error});
  final String source;
  final ImportOutcome outcome;

  /// Arquivo na pasta do Lume (o novo ou o que já existia igual).
  final String? dest;
  final String? error;
  String get name => p.basename(source);
}

class ImportProgress {
  const ImportProgress(this.index, this.total, this.name, this.bytesDone, this.bytesTotal);
  final int index, total; // arquivo atual (0 = primeiro)
  final String name;
  final int bytesDone, bytesTotal; // de todos os arquivos
  double get fraction => bytesTotal == 0 ? (total == 0 ? 1 : index / total) : bytesDone / bytesTotal;
}

class BookImporter {
  BookImporter(this.dest);
  final Directory dest;
  final Map<String, String> _hashes = {}; // caminho → sha1 (cache)

  static Future<String> hashFile(String path) async => (await sha1.bind(File(path).openRead()).first).toString();

  /// Nome livre na pasta: "nome.ext", "nome (2).ext", "nome (3).ext"…
  static String freeName(Directory dir, String name) {
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    var candidate = name;
    for (var n = 2; File(p.join(dir.path, candidate)).existsSync() || File(p.join(dir.path, '$candidate.part')).existsSync(); n++) {
      candidate = '$base ($n)$ext';
    }
    return candidate;
  }

  /// Arquivo da pasta com o mesmo conteúdo (só compara os de mesmo tamanho).
  Future<String?> findSame(String source) async {
    if (!dest.existsSync()) return null;
    final size = await File(source).length();
    String? srcHash;
    await for (final e in dest.list(recursive: true, followLinks: false)) {
      if (e is! File || !isBookPath(e.path)) continue;
      if (p.canonicalize(e.path) == p.canonicalize(source)) return e.path;
      int len;
      try {
        len = await e.length();
      } catch (_) {
        continue;
      }
      if (len != size) continue;
      srcHash ??= await hashFile(source);
      final h = _hashes[e.path] ??= await hashFile(e.path);
      if (h == srcHash) return e.path;
    }
    return null;
  }

  /// Copia os arquivos para a pasta do Lume, um de cada vez.
  Future<List<ImportItem>> importAll(List<String> sources, {void Function(ImportProgress)? onProgress}) async {
    await dest.create(recursive: true);
    final sizes = <int>[];
    for (final s in sources) {
      try {
        sizes.add(await File(s).length());
      } catch (_) {
        sizes.add(0);
      }
    }
    final total = sizes.fold<int>(0, (a, b) => a + b);
    var done = 0;
    final out = <ImportItem>[];
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      final name = p.basename(src);
      onProgress?.call(ImportProgress(i, sources.length, name, done, total));
      try {
        if (!isBookPath(src)) {
          out.add(ImportItem(src, ImportOutcome.unsupported));
        } else {
          final same = await findSame(src);
          if (same != null) {
            out.add(ImportItem(src, ImportOutcome.duplicate, dest: same));
          } else {
            final target = File(p.join(dest.path, freeName(dest, name)));
            final part = File('${target.path}.part');
            final sink = part.openWrite();
            final base = done;
            try {
              await for (final chunk in File(src).openRead()) {
                sink.add(chunk);
                done += chunk.length;
                onProgress?.call(ImportProgress(i, sources.length, name, done, total));
              }
              await sink.close();
            } catch (_) {
              await sink.close();
              if (part.existsSync()) part.deleteSync();
              done = base;
              rethrow;
            }
            await part.rename(target.path);
            out.add(ImportItem(src, ImportOutcome.added, dest: target.path));
          }
        }
      } catch (e) {
        out.add(ImportItem(src, ImportOutcome.failed, error: '$e'));
      }
      done = sizes.take(i + 1).fold(0, (a, b) => a + b);
    }
    onProgress?.call(ImportProgress(sources.length, sources.length, '', total, total));
    return out;
  }
}
