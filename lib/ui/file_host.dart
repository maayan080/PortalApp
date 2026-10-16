import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// the device side of file transfers, so the pages do not care which platform they run on
abstract class FileHost {
  Future<List<File>> pickUploads();

  // where a download should be written, or null when the user backs out
  Future<File?> downloadTarget(String name);

  // runs after a download completes, returns a line to show the user
  Future<String> finished(File saved);
}

class DeviceFileHost implements FileHost {
  @override
  Future<List<File>> pickUploads() async {
    final picked = await FilePicker.pickFiles();
    return [for (final f in picked) if (f.path != null) File(f.path!)];
  }

  @override
  Future<File?> downloadTarget(String name) async {
    if (Platform.isAndroid || Platform.isIOS) {
      // phones get a private copy first, then the share sheet moves it somewhere useful
      final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}downloads');
      await dir.create(recursive: true);
      return File('${dir.path}${Platform.pathSeparator}$name');
    }
    final folder = await FilePicker.getDirectoryPath(dialogTitle: 'Save $name to');
    if (folder == null) return null;
    return _unique(folder, name);
  }

  @override
  Future<String> finished(File saved) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await SharePlus.instance.share(ShareParams(files: [XFile(saved.path)]));
      return 'Downloaded ${saved.uri.pathSegments.last}';
    }
    return 'Saved to ${saved.path}';
  }

  // never overwrite a file the user already has
  static File _unique(String folder, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var f = File('$folder${Platform.pathSeparator}$name');
    for (var i = 1; f.existsSync(); i++) {
      f = File('$folder${Platform.pathSeparator}$stem ($i)$ext');
    }
    return f;
  }
}
