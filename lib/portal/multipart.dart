import 'dart:convert';
import 'dart:io';

// one file part of a multipart body, streamed from disk so a 600 MB package never sits in memory
class MultipartFile {
  MultipartFile(this.file, [String? name]) : name = name ?? file.uri.pathSegments.last;

  final File file;
  final String name;

  // utf8 like a browser sends it, with the characters that would end the quoted value escaped
  List<int> get head {
    final n = name.replaceAll('"', '%22').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
    return utf8.encode('Content-Disposition: form-data; name="$n"; filename="$n"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n');
  }
}

const _crlf = [13, 10];

class MultipartBody {
  MultipartBody(this.files, {String? boundary}) : boundary = boundary ?? _newBoundary();

  final List<MultipartFile> files;
  final String boundary;

  String get contentType => 'multipart/form-data; boundary=$boundary';

  static String _newBoundary() => '----portalapp${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';

  List<int> _opening(MultipartFile f) => [...ascii.encode('--$boundary\r\n'), ...f.head];

  List<int> get _closing => ascii.encode('--$boundary--\r\n');

  // the portal wants a content length, chunked bodies are not worth the risk
  Future<int> length() async {
    var n = _closing.length;
    for (final f in files) {
      n += _opening(f).length + await f.file.length() + _crlf.length;
    }
    return n;
  }

  Stream<List<int>> stream() async* {
    for (final f in files) {
      yield _opening(f);
      yield* f.file.openRead();
      yield _crlf;
    }
    yield _closing;
  }
}
