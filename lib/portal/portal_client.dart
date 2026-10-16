import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'models.dart';
import 'multipart.dart';

export 'models.dart';

typedef Progress = void Function(int done, int total);

// talks to the xbox dev mode device portal, https on 11443 with a self-signed certificate.
// no flutter imports on purpose, so it can run from the dart cli and from the app alike
class PortalClient {
  PortalClient(this.address, {this.port = 11443, this.username, this.password}) {
    // the certificate is self-signed, so accept it, but only for this console
    _http.badCertificateCallback = (cert, host, p) => host == address && p == port;
    _http.connectionTimeout = const Duration(seconds: 8);
  }

  final String address;
  final int port;
  final String? username;
  final String? password;

  final HttpClient _http = HttpClient();
  final Map<String, String> _cookies = {};
  String? _csrf;

  // the line shown under Connected on the Console tab
  String describe(int packageCount) => '$address:$port  ·  $packageCount packages';

  String get base => 'https://$address:$port';

  // quick reachability check before a full connect, a closed port fails fast
  static Future<bool> reachable(String address, {int port = 11443, Duration timeout = const Duration(milliseconds: 2500)}) async {
    try {
      final s = await Socket.connect(address, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  // GET / hands out the CSRF-Token cookie. every POST and DELETE must send it back as
  // X-CSRF-Token on the same session, without it the portal answers 403 or reports success
  // and does nothing at all
  Future<void> connect() async {
    _cookies.clear();
    _csrf = null;
    final r = await _request('GET', '/', timeout: const Duration(seconds: 20));
    _check(r, 'connect');
    _csrf = _cookies['CSRF-Token'];
    if (_csrf == null) throw PortalException('no CSRF-Token from the device portal at $base');
  }

  void close() => _http.close(force: true);

  // apps

  Future<List<InstalledPackage>> packages() async {
    final j = await _json('GET', '/api/app/packagemanager/packages');
    return [
      for (final p in (j['InstalledPackages'] as List? ?? const [])) InstalledPackage.fromJson((p as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<InstalledPackage>> findFamily(String familyPrefix) async => matchFamily(await packages(), familyPrefix);

  Future<InstallState> installState() async => InstallState.fromJson(await _json('GET', '/api/app/packagemanager/state'));

  // uploads the package and waits for the portal to register it. always in place, never
  // uninstall first, that destroys LocalState. any extra file goes up as a dependency
  Future<InstalledPackage> install(
    File package, {
    List<File> dependencies = const [],
    required String familyPrefix,
    String? expectedVersion,
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    var bytes = await package.length();
    for (final d in dependencies) {
      bytes += await d.length();
    }
    // a 600 MB package registers a lot slower than a 12 MB one, so both timeouts scale
    final mb = (bytes / (1024 * 1024)).ceil();
    final uploadTimeout = Duration(seconds: max(300, mb * 3));
    final registerTimeout = Duration(seconds: max(240, mb * 2));

    final name = package.uri.pathSegments.last;
    final body = MultipartBody([MultipartFile(package), for (final d in dependencies) MultipartFile(d)]);
    final r = await _request('POST', '/api/app/packagemanager/package?package=${Uri.encodeComponent(name)}',
        multipart: body, timeout: uploadTimeout, onSent: onUpload);
    _check(r, 'upload of $name');

    final deadline = DateTime.now().add(registerTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      InstallState st;
      try {
        st = await installState();
      } on PortalException {
        // the portal can be busy registering, try again until the deadline
        continue;
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      } on HttpException {
        continue;
      }
      onState?.call(st);
      if (st.done) break;
      if (!st.working && !st.success) {
        throw PortalException('install failed ${st.code}: ${st.reason} ${st.codeText}'.trim());
      }
    }

    // old and new both list briefly mid-registration, so match the wanted version. the list can lag
    // the state by a moment, so look a few times before calling it a failure
    for (var attempt = 0; attempt < 5; attempt++) {
      if (attempt > 0) await Future<void>.delayed(const Duration(seconds: 2));
      final after = await findFamily(familyPrefix);
      final hit = expectedVersion == null
          ? (after.isEmpty ? null : after.first)
          : after.where((p) => p.fullName.contains('_${expectedVersion}_')).firstOrNull;
      if (hit != null) return hit;
    }
    throw PortalException('The console accepted the package, but ${expectedVersion ?? 'the new version'} is not in its app list. '
        'Refresh the Installed list to check.');
  }

  Future<void> uninstall(InstalledPackage p) async {
    final r = await _request('DELETE', '/api/app/packagemanager/package?package=${Uri.encodeComponent(p.fullName)}');
    _check(r, 'delete ${p.name}');
  }

  Future<void> launch(InstalledPackage p) async {
    final r = await _request('POST', '/api/taskmanager/app?appid=${_b64(p.relativeId)}&package=${_b64(p.fullName)}',
        timeout: const Duration(seconds: 60));
    _check(r, 'launch ${p.name}');
  }

  // false when the portal refuses, which is what it does for an app that is not running
  Future<bool> closeApp(InstalledPackage p) async {
    final r = await _request('DELETE', '/api/taskmanager/app?package=${_b64(p.fullName)}', timeout: const Duration(seconds: 60));
    return r.status < 400;
  }

  // full names of packages with a running process
  Future<Set<String>> runningPackages() async {
    final j = await _json('GET', '/api/resourcemanager/processes');
    return {
      for (final p in (j['Processes'] as List? ?? const []))
        if (p is Map && p['IsRunning'] == true && p['PackageFullName'] is String) p['PackageFullName'] as String,
    };
  }

  // files, always inside one app's LocalAppData

  static String _fileQuery(InstalledPackage p) => 'knownfolderid=LocalAppData&packagefullname=${Uri.encodeComponent(p.fullName)}';

  static String _enc(String s) => Uri.encodeComponent(s);

  Future<List<FileEntry>> listFiles(InstalledPackage p, {String path = r'\LocalState'}) async {
    final j = await _json('GET', '/api/filesystem/apps/files?${_fileQuery(p)}&path=${_enc(path)}');
    return [
      for (final i in (j['Items'] as List? ?? const [])) FileEntry.fromJson((i as Map).cast<String, dynamic>(), path),
    ];
  }

  Future<File> download(InstalledPackage p, String name, File dest, {String path = r'\LocalState', Progress? onProgress}) async {
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    final sink = part.openWrite();
    try {
      final resp = await _open('GET', '/api/filesystem/apps/file?${_fileQuery(p)}&filename=${_enc(name)}&path=${_enc(path)}',
          timeout: const Duration(minutes: 30));
      if (resp.statusCode >= 400) {
        final text = utf8.decode(await _drain(resp), allowMalformed: true);
        throw PortalException('download of $name failed: ${_trim(text)}', status: resp.statusCode);
      }
      var got = 0;
      await resp.map((c) {
        got += c.length;
        onProgress?.call(got, resp.contentLength);
        return c;
      }).pipe(sink);
    } catch (_) {
      await sink.close().catchError((_) {});
      if (await part.exists()) await part.delete();
      rethrow;
    }
    if (await dest.exists()) await dest.delete();
    return part.rename(dest.path);
  }

  Future<void> upload(InstalledPackage p, File file, {String path = r'\LocalState', Progress? onProgress}) async {
    final r = await _request('POST', '/api/filesystem/apps/file?${_fileQuery(p)}&path=${_enc(path)}',
        multipart: MultipartBody([MultipartFile(file)]), timeout: const Duration(minutes: 30), onSent: onProgress);
    _check(r, 'upload of ${file.uri.pathSegments.last}');
  }

  Future<void> deleteFile(InstalledPackage p, String name, {String path = r'\LocalState'}) async {
    final r = await _request('DELETE', '/api/filesystem/apps/file?${_fileQuery(p)}&filename=${_enc(name)}&path=${_enc(path)}');
    _check(r, 'delete of $name');
  }

  // one level only. the portal answers 400 when it already exists, which counts as made
  Future<void> makeFolder(InstalledPackage p, String parent, String name) async {
    await _request('POST', '/api/filesystem/apps/folder?${_fileQuery(p)}&path=${_enc(parent)}&newfoldername=${_enc(name)}');
  }

  // nested folders have to be made one level at a time
  Future<void> makeFolders(InstalledPackage p, String path) async {
    var parent = r'\';
    for (final part in path.split(r'\').where((s) => s.isNotEmpty)) {
      await makeFolder(p, parent, part);
      parent = parent == r'\' ? '\\$part' : '$parent\\$part';
    }
  }

  // the console screen as the portal serves it, png or jpeg depending on the build
  Future<Uint8List> screenshot() async {
    final r = await _request('GET', '/ext/screenshot?download=true&hdr=false', timeout: const Duration(seconds: 30));
    _check(r, 'screenshot');
    return r.bytes;
  }

  // plumbing

  static String _b64(String s) => base64.encode(utf8.encode(s));

  static String _trim(String s) {
    final t = s.trim();
    return t.length > 300 ? '${t.substring(0, 300)}...' : t;
  }

  void _check(_Reply r, String what) {
    if (r.status == 401) {
      throw PortalException('the portal wants a username and password', status: 401);
    }
    if (r.status >= 400) {
      throw PortalException('$what failed: ${_trim(utf8.decode(r.bytes, allowMalformed: true))}', status: r.status);
    }
  }

  Future<Map<String, dynamic>> _json(String method, String path) async {
    final r = await _request(method, path);
    _check(r, path);
    final text = utf8.decode(r.bytes, allowMalformed: true).trim();
    if (text.isEmpty) return {};
    final j = jsonDecode(text);
    return j is Map ? j.cast<String, dynamic>() : {'value': j};
  }

  Future<Uint8List> _drain(HttpClientResponse resp) async {
    final b = BytesBuilder(copy: false);
    await for (final c in resp) {
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<_Reply> _request(
    String method,
    String path, {
    MultipartBody? multipart,
    Duration timeout = const Duration(seconds: 30),
    Progress? onSent,
  }) async {
    final resp = await _open(method, path, multipart: multipart, timeout: timeout, onSent: onSent);
    final bytes = await _drain(resp).timeout(timeout);
    return _Reply(resp.statusCode, bytes);
  }

  // opens the request and returns the response headers, the caller drains the body
  Future<HttpClientResponse> _open(
    String method,
    String path, {
    MultipartBody? multipart,
    required Duration timeout,
    Progress? onSent,
  }) async {
    final req = await _http.openUrl(method, Uri.parse('$base$path')).timeout(timeout);
    try {
      if (username != null) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Basic ${_b64('$username:${password ?? ''}')}');
      }
      if (_cookies.isNotEmpty) {
        req.headers.set(HttpHeaders.cookieHeader, _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '));
      }
      if (method != 'GET' && _csrf != null) req.headers.set('X-CSRF-Token', _csrf!);

      if (multipart != null) {
        final total = await multipart.length();
        req.headers.set(HttpHeaders.contentTypeHeader, multipart.contentType);
        req.contentLength = total;
        var sent = 0;
        await req.addStream(multipart.stream().map((c) {
          sent += c.length;
          onSent?.call(sent, total);
          return c;
        })).timeout(timeout);
      } else if (method != 'GET') {
        req.contentLength = 0;
      }

      final resp = await req.close().timeout(timeout);
      for (final c in resp.cookies) {
        _cookies[c.name] = c.value;
      }
      return resp;
    } catch (_) {
      // a timed out request is still holding its socket
      req.abort();
      rethrow;
    }
  }
}

class _Reply {
  _Reply(this.status, this.bytes);

  final int status;
  final Uint8List bytes;
}
