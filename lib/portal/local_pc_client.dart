import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

import 'package_info.dart';
import 'portal_client.dart';

class LocalPcClient extends PortalClient {
  LocalPcClient() : super('this PC');

  static bool get available => Platform.isWindows;

  @override
  String get base => 'this PC';

  @override
  String describe(int packageCount) => 'This PC (test)  ·  $packageCount packages';

  @override
  Future<void> connect() async {
    if (!available) throw PortalException('Testing on this PC needs Windows.');
    await _ps('1');
  }

  @override
  void close() {}

  static String _q(String s) => "'${s.replaceAll("'", "''")}'";

  Future<String> _ps(String script) async {
    final r = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', "\$ErrorActionPreference='Stop'; \$ProgressPreference='SilentlyContinue'; $script"],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) {
      final err = (r.stderr as String).trim();
      throw PortalException(_tidy(err.isEmpty ? 'PowerShell exited with ${r.exitCode}.' : err));
    }
    return (r.stdout as String).trim();
  }

  static String _tidy(String err) {
    final line = err.split(RegExp(r'\r?\n')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => err).trim();
    return line.length > 400 ? '${line.substring(0, 400)}...' : line;
  }

  @override
  Future<List<InstalledPackage>> packages() async {
    final out = await _ps(
        "@(Get-AppxPackage | ForEach-Object { [pscustomobject]@{ F=\$_.PackageFullName; Fam=\$_.PackageFamilyName; N=\$_.Name; P=\$_.Publisher; V=\$_.Version.ToString(); S=[string]\$_.SignatureKind; D=\$_.IsDevelopmentMode; L=\$_.InstallLocation } }) | ConvertTo-Json -Compress");
    if (out.isEmpty) return [];
    final decoded = jsonDecode(out);
    final list = decoded is List ? decoded : [decoded];
    return [
      for (final p in list.cast<Map<String, dynamic>>())
        InstalledPackage(
          fullName: p['F'] as String,
          familyName: p['Fam'] as String,
          relativeId: p['Fam'] as String,
          name: p['N'] as String,
          publisher: p['P'] as String? ?? '',
          version: PackageVersion.tryParse(p['V'] as String? ?? '') ?? const PackageVersion(0, 0, 0, 0),
          origin: switch (p['S']) {
            'System' => 2,
            'Store' => 3,
            'Enterprise' => 6,
            _ => 5,
          },
          canUninstall: p['S'] != 'System',
          uninstallDeniedReason: p['S'] == 'System' ? 'This is part of Windows.' : '',
          listed: true,
          users: const [],
        ),
    ];
  }

  @override
  Future<InstallState> installState() async => const InstallState(code: 0, success: true, codeText: '', reason: '');

  @override
  Future<InstalledPackage> install(
    File package, {
    List<File> dependencies = const [],
    required String familyPrefix,
    String? expectedVersion,
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    final size = await package.length();
    onUpload?.call(0, size);
    onUpload?.call(size, size);

    final present = await packages();
    for (final dep in dependencies) {
      final info = await readPackageInfo(dep);
      if (present.any((p) => p.name == info.name && p.version.compareTo(info.version) >= 0)) continue;
      await _register(dep, info);
    }
    await _register(package, await readPackageInfo(package));

    final after = matchFamily(await packages(), familyPrefix);
    final hit = expectedVersion == null
        ? (after.isEmpty ? null : after.first)
        : after.where((p) => p.fullName.contains('_${expectedVersion}_')).firstOrNull;
    if (hit != null) return hit;
    throw PortalException('Windows accepted the package, but ${expectedVersion ?? 'the new version'} is not in its app list.');
  }

  Future<void> _register(File file, PackageInfo info) async {
    final dir = Directory('${_root.path}${Platform.pathSeparator}${info.name}_${info.version}');
    await _unpack(file, dir);
    await _ps('Add-AppxPackage -Register ${_q('${dir.path}${Platform.pathSeparator}AppxManifest.xml')} -ForceApplicationShutdown -ForceUpdateFromAnyVersion');
  }

  static Directory get _root =>
      Directory('${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}${Platform.pathSeparator}PortalApp${Platform.pathSeparator}pc_test');

  static const _skipped = {'[content_types].xml', 'appxblockmap.xml', 'appxsignature.p7x'};

  static Future<void> _unpack(File file, Directory into) async {
    await into.create(recursive: true);
    final input = InputFileStream(file.path);
    try {
      final zip = ZipDecoder().decodeStream(input);
      final bundle = zip.find('AppxMetadata/AppxBundleManifest.xml');
      if (bundle != null) {
        final inner = _pickFromBundle(String.fromCharCodes(bundle.readBytes() ?? const []));
        final entry = inner == null ? null : zip.find(inner);
        if (entry == null) throw PortalException('There is no app inside ${file.uri.pathSegments.last} for this PC.');
        final tmp = File('${into.path}${Platform.pathSeparator}_inner.pkg');
        final out = OutputFileStream(tmp.path);
        entry.writeContent(out);
        await out.close();
        try {
          await _unpack(tmp, into);
        } finally {
          await tmp.delete();
        }
        return;
      }
      final base = into.absolute.path;
      for (final f in zip.files) {
        if (!f.isFile) continue;
        final name = Uri.decodeFull(f.name);
        if (_skipped.contains(name.toLowerCase())) continue;
        final target = File('$base${Platform.pathSeparator}${name.replaceAll('/', Platform.pathSeparator)}').absolute;
        if (!target.path.startsWith(base)) continue;
        await target.parent.create(recursive: true);
        final out = OutputFileStream(target.path);
        f.writeContent(out);
        await out.close();
      }
    } finally {
      await input.close();
    }
  }

  static String? _pickFromBundle(String manifest) {
    final xml = XmlDocument.parse(manifest.replaceAll('﻿', ''));
    final apps = [
      for (final e in xml.findAllElements('Package'))
        if ((e.getAttribute('Type') ?? 'application') == 'application' && e.getAttribute('FileName') != null) e,
    ];
    for (final arch in ['x64', 'neutral']) {
      final hit = apps.where((e) => (e.getAttribute('Architecture') ?? 'neutral').toLowerCase() == arch).firstOrNull;
      if (hit != null) return hit.getAttribute('FileName');
    }
    return null;
  }

  @override
  Future<void> uninstall(InstalledPackage p) async {
    final where = await _ps("(Get-AppxPackage | Where-Object PackageFullName -eq ${_q(p.fullName)}).InstallLocation");
    await _ps('Remove-AppxPackage -Package ${_q(p.fullName)}');
    if (where.isNotEmpty && where.toLowerCase().startsWith(_root.absolute.path.toLowerCase())) {
      try {
        await Directory(where).delete(recursive: true);
      } catch (_) {}
    }
  }

  @override
  Future<void> launch(InstalledPackage p) => _ps(
      "\$id=(Get-AppxPackageManifest -Package ${_q(p.fullName)}).Package.Applications.Application | Select-Object -First 1 -ExpandProperty Id; Start-Process (${_q('shell:AppsFolder\\${p.familyName}!')} + \$id)");

  @override
  Future<bool> closeApp(InstalledPackage p) async {
    try {
      await _ps(
          "\$l=(Get-AppxPackage -PackageTypeFilter Main | Where-Object PackageFullName -eq ${_q(p.fullName)}).InstallLocation; \$n=Get-Process | Where-Object { \$_.Path -and \$_.Path.StartsWith(\$l) }; if(-not \$n){ exit 1 }; \$n | Stop-Process -Force");
      return true;
    } on PortalException {
      return false;
    }
  }

  @override
  Future<Set<String>> runningPackages() async => {};

  @override
  Future<List<FileEntry>> listFiles(InstalledPackage p, {String path = r'\LocalState'}) async => [];

  @override
  Future<Uint8List> screenshot() => throw PortalException('There is no console screen on this PC.');

  @override
  Future<File> download(InstalledPackage p, String name, File dest, {String path = r'\LocalState', Progress? onProgress}) =>
      throw PortalException('App files are only available on a console.');

  @override
  Future<void> upload(InstalledPackage p, File file, {String path = r'\LocalState', Progress? onProgress}) =>
      throw PortalException('App files are only available on a console.');

  @override
  Future<void> deleteFile(InstalledPackage p, String name, {String path = r'\LocalState'}) =>
      throw PortalException('App files are only available on a console.');

  @override
  Future<void> makeFolder(InstalledPackage p, String parent, String name) =>
      throw PortalException('App files are only available on a console.');

  @override
  Future<void> makeFolders(InstalledPackage p, String path) =>
      throw PortalException('App files are only available on a console.');
}
