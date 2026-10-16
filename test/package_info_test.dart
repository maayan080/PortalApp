import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/portal/install_plan.dart';
import 'package:portal_app/portal/models.dart';
import 'package:portal_app/portal/package_info.dart';

const _manifest = '''<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Acme.Widget" Publisher="CN=Acme" Version="1.2.3.4" ProcessorArchitecture="x64" />
  <Properties><DisplayName>DISPLAY</DisplayName></Properties>
</Package>''';

Future<File> makePackage(Directory dir, String name, {String display = 'Widget', bool signed = true, String? manifest, bool bundle = false}) async {
  final a = Archive();
  void add(String path, String text) => a.addFile(ArchiveFile.bytes(path, utf8.encode(text)));
  final xml = manifest ?? _manifest.replaceFirst('DISPLAY', display);
  if (bundle) {
    add('AppxMetadata/AppxBundleManifest.xml', xml);
  } else {
    add('AppxManifest.xml', xml);
  }
  if (signed) add('AppxSignature.p7x', 'sig');
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(ZipEncoder().encode(a));
  return f;
}

InstalledPackage installed(String family, String version) => InstalledPackage(
      fullName: '${family}_${version}_x64__abc',
      familyName: family,
      relativeId: '',
      name: family,
      publisher: '',
      version: PackageVersion.tryParse(version)!,
      origin: 5,
      canUninstall: true,
      uninstallDeniedReason: '',
      listed: true,
      users: const [],
    );

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('pkginfo'));
  tearDown(() => dir.delete(recursive: true));

  test('reads identity, display name and signature', () async {
    final info = await readPackageInfo(await makePackage(dir, 'w.appx'));
    expect(info.name, 'Acme.Widget');
    expect(info.displayName, 'Widget');
    expect(info.version.toString(), '1.2.3.4');
    expect(info.architecture, 'x64');
    expect(info.signed, isTrue);
    expect(info.isBundle, isFalse);
    expect(info.familyPrefix, 'Acme.Widget');
  });

  test('flags an unsigned package', () async {
    final info = await readPackageInfo(await makePackage(dir, 'w.appx', signed: false));
    expect(info.signed, isFalse);
    expect(planInstall(info, []).allowed, isFalse);
  });

  test('resource string display names fall back to the identity name', () async {
    final info = await readPackageInfo(await makePackage(dir, 'w.appx', display: 'ms-resource:AppName'));
    expect(info.displayName, 'Acme.Widget');
  });

  test('reads a bundle manifest', () async {
    final info = await readPackageInfo(await makePackage(dir, 'w.msixbundle', bundle: true));
    expect(info.isBundle, isTrue);
    expect(info.name, 'Acme.Widget');
  });

  test('rejects files that are not packages', () async {
    final junk = File('${dir.path}/junk.appx')..writeAsStringSync('not a zip');
    expect(readPackageInfo(junk), throwsA(isA<PackageFormatException>()));
    final empty = await makePackage(dir, 'e.appx', manifest: '<Package/>');
    expect(readPackageInfo(empty), throwsA(isA<PackageFormatException>()));
  });

  test('plans fresh, update, reinstall and downgrade', () async {
    final info = await readPackageInfo(await makePackage(dir, 'w.appx'));
    expect(planInstall(info, []).kind, InstallKind.fresh);
    expect(planInstall(info, [installed('Other.App', '9.0.0.0')]).kind, InstallKind.fresh);
    expect(planInstall(info, [installed('Acme.Widget', '1.2.3.3')]).kind, InstallKind.update);
    expect(planInstall(info, [installed('Acme.Widget', '1.2.3.4')]).kind, InstallKind.reinstall);
    expect(planInstall(info, [installed('Acme.Widget', '1.2.3.5')]).kind, InstallKind.downgrade);
    // 1.2.3.4 against 1.2.3.30 is numeric, not text
    expect(planInstall(info, [installed('Acme.Widget', '1.2.3.30')]).kind, InstallKind.downgrade);
  });
}
