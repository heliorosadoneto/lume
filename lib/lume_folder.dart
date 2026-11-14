// A pasta de livros do próprio Lume. De preferência em Documentos/Lume, que
// aparece no gerenciador de arquivos; se o Android não deixar criar, fica na
// pasta do app no armazenamento (Android/data/com.helio.lume/files/Livros).
import 'dart:io';

import 'package:path/path.dart' as p;

enum LumeFolderKind {
  /// Documentos/Lume: visível no gerenciador de arquivos.
  documents,

  /// Android/data/com.helio.lume/files/Livros: alguns gerenciadores escondem
  /// e o Android apaga ao desinstalar o app.
  appExternal,

  /// Pasta interna do app (sem armazenamento externo; testes e desktop).
  internal,
}

class LumeFolder {
  const LumeFolder(this.dir, this.kind);
  final Directory dir;
  final LumeFolderKind kind;
  String get path => dir.path;

  /// Raiz do armazenamento compartilhado a partir da pasta externa do app
  /// (/storage/emulated/0/Android/data/(pacote)/files → /storage/emulated/0).
  static String? sharedRoot(String? appExternal) {
    if (appExternal == null) return null;
    final i = appExternal.indexOf('${p.separator}Android${p.separator}data${p.separator}');
    return i <= 0 ? null : appExternal.substring(0, i);
  }

  /// Tenta criar a pasta e gravar nela (o jeito certo de saber se o Android deixa).
  static bool usable(Directory d) {
    try {
      d.createSync(recursive: true);
      final probe = File(p.join(d.path, '.lume-teste'));
      probe.writeAsStringSync('ok');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Escolhe a pasta: Documentos/Lume → pasta externa do app → interna.
  static LumeFolder resolve({String? appExternal, required String internal, bool Function(Directory)? canUse}) {
    final ok = canUse ?? usable;
    final root = sharedRoot(appExternal);
    if (root != null) {
      final docs = Directory(p.join(root, 'Documents', 'Lume'));
      if (ok(docs)) return LumeFolder(docs, LumeFolderKind.documents);
    }
    if (appExternal != null) {
      final ext = Directory(p.join(appExternal, 'Livros'));
      if (ok(ext)) return LumeFolder(ext, LumeFolderKind.appExternal);
    }
    final dir = Directory(internal)..createSync(recursive: true);
    return LumeFolder(dir, LumeFolderKind.internal);
  }

  /// Leva os livros de uma pasta antiga para a nova (copia, confere o tamanho e
  /// só então apaga o original). Arquivo com o mesmo nome e tamanho já
  /// presente no destino não é copiado de novo. Devolve quantos foram movidos.
  static int migrate(Directory from, Directory to, bool Function(String) isBook) {
    if (!from.existsSync() || p.canonicalize(from.path) == p.canonicalize(to.path)) return 0;
    var moved = 0;
    to.createSync(recursive: true);
    for (final e in from.listSync(followLinks: false)) {
      if (e is! File || !isBook(e.path)) continue;
      try {
        final len = e.lengthSync();
        final same = File(p.join(to.path, p.basename(e.path)));
        if (same.existsSync() && same.lengthSync() == len) {
          e.deleteSync();
          continue;
        }
        var target = same;
        for (var n = 2; target.existsSync(); n++) {
          target = File(p.join(to.path, '${p.basenameWithoutExtension(e.path)} ($n)${p.extension(e.path)}'));
        }
        e.copySync(target.path);
        if (target.lengthSync() == len) {
          e.deleteSync();
          moved++;
        }
      } catch (_) {
        // fica na pasta antiga; a biblioteca continua lendo de lá
      }
    }
    return moved;
  }
}
