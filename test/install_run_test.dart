import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/install_run.dart';
import 'package:portal_app/catalog/models.dart';
import 'package:portal_app/portal/package_info.dart';
import 'package:portal_app/portal/portal_client.dart';
import 'package:portal_app/state/console_session.dart';

List<int> appxBytes(String version, {bool signed = true}) {
  final a = Archive();
  a.addFile(ArchiveFile.bytes(
      'AppxManifest.xml',
      utf8.encode('<Package><Identity Name="Acme.Widget" Publisher="CN=Acme" Version="$version" ProcessorArchitecture="x64"/>'
          '<Properties><DisplayName>Widget</DisplayName></Properties></Package>')));
  if (signed) a.addFile(ArchiveFile.bytes('AppxSignature.p7x', [1]));
  return ZipEncoder().encode(a);
}

// a catalogue that serves bytes from memory and records what was fetched
class FakeCatalog extends CatalogClient {
  FakeCatalog(this.files, {this.checksum}) : super('https://example.com/');

  final Map<String, List<int>> files;
  final String? checksum;
  final fetched = <String>[];
  Duration delay = Duration.zero;

  @override
  Future<File> download(Uri uri, File dest, {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    final name = uri.pathSegments.last;
    fetched.add(name);
    await Future<void>.delayed(delay);
    if (cancel?.cancelled ?? false) throw CancelledException();
    final bytes = files[name]!;
    await dest.writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
    return dest;
  }

  @override
  Future<String> checksumFor(CatalogApp app, CatalogDownload d) async => checksum!;
}

class FakeConsole extends PortalClient {
  FakeConsole() : super('10.0.0.1');

  final installs = <String>[];

  @override
  Future<List<InstalledPackage>> packages() async => [];

  @override
  Future<Set<String>> runningPackages() async => {};

  @override
  Future<InstalledPackage> install(
    File package, {
    List<File> dependencies = const [],
    required String familyPrefix,
    String? expectedVersion,
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    installs.add('${package.uri.pathSegments.last} deps=${dependencies.map((d) => d.uri.pathSegments.last).join('|')}');
    onUpload?.call(10, 100);
    onUpload?.call(100, 100);
    return InstalledPackage.fromJson({
      'PackageFullName': 'Acme.Widget_${expectedVersion}_x64__abc',
      'PackageFamilyName': 'Acme.Widget',
      'Name': 'Widget',
      'PackageOrigin': 5,
      'AppListEntry': 1,
      'Version': {'Major': 1, 'Minor': 0, 'Build': 0, 'Revision': 4},
    });
  }
}

CatalogApp app({bool withChecksum = true, bool withDependency = false}) => CatalogApp.fromJson('widget', Uri.parse('https://example.com/projects/widget/'), {
      'name': 'Widget',
      'version': '1.0.0.4',
      'downloads': [
        {'label': 'Download APPX', 'file': 'Widget.appx'},
        if (withDependency) {'label': 'Download VCLibs dependency', 'file': 'Microsoft.VCLibs.appx'},
        if (withChecksum) {'label': 'SHA-256 checksum', 'file': 'Widget.appx.sha256'},
      ],
    });

void main() {
  test('downloads, checks, sends and installs, then cleans up', () async {
    final bytes = appxBytes('1.0.0.4');
    final catalog = FakeCatalog({'Widget.appx': bytes}, checksum: sha256.convert(bytes).toString());
    final console = FakeConsole();
    PackageInfo? learned;
    final run = InstallRun(app: app(), catalog: catalog, session: ConsoleSession(console), onInstalled: (a, i) => learned = i);

    await run.start();

    expect(run.failed, isFalse, reason: run.error);
    expect(run.finished, isTrue);
    expect(run.steps.map((s) => s.state), everyElement(StepStatus.done));
    expect(run.steps[1].detail, contains('checksum matches'));
    expect(console.installs, ['Widget.appx deps=']);
    expect(run.result!.name, 'Widget');
    expect(learned!.name, 'Acme.Widget');
  });

  test('a download that does not match its checksum is not installed', () async {
    final catalog = FakeCatalog({'Widget.appx': appxBytes('1.0.0.4')}, checksum: 'a' * 64);
    final console = FakeConsole();
    final run = InstallRun(app: app(), catalog: catalog, session: ConsoleSession(console));

    await run.start();

    expect(run.failed, isTrue);
    expect(run.error, contains('checksum'));
    expect(run.steps[1].state, StepStatus.failed);
    expect(run.steps[2].state, StepStatus.pending);
    expect(console.installs, isEmpty);
  });

  test('an unsigned package is refused before it is sent', () async {
    final catalog = FakeCatalog({'Widget.appx': appxBytes('1.0.0.4', signed: false)});
    final console = FakeConsole();
    final run = InstallRun(app: app(withChecksum: false), catalog: catalog, session: ConsoleSession(console));

    await run.start();

    expect(run.error, contains('not signed'));
    expect(console.installs, isEmpty);
  });

  test('no published checksum is said plainly, and still installs', () async {
    final catalog = FakeCatalog({'Widget.appx': appxBytes('1.0.0.4')});
    final console = FakeConsole();
    final run = InstallRun(app: app(withChecksum: false), catalog: catalog, session: ConsoleSession(console));

    await run.start();

    expect(run.failed, isFalse, reason: run.error);
    expect(run.steps[1].detail, contains('no checksum'));
    expect(console.installs, hasLength(1));
  });

  test('dependencies are downloaded and sent with the app', () async {
    final catalog = FakeCatalog({'Widget.appx': appxBytes('1.0.0.4'), 'Microsoft.VCLibs.appx': [1, 2, 3]});
    final console = FakeConsole();
    final run = InstallRun(app: app(withChecksum: false, withDependency: true), catalog: catalog, session: ConsoleSession(console));

    await run.start();

    expect(run.failed, isFalse, reason: run.error);
    expect(catalog.fetched, ['Widget.appx', 'Microsoft.VCLibs.appx']);
    expect(console.installs.single, 'Widget.appx deps=Microsoft.VCLibs.appx');
  });

  test('cancelling during the download installs nothing', () async {
    final catalog = FakeCatalog({'Widget.appx': appxBytes('1.0.0.4')})..delay = const Duration(milliseconds: 50);
    final console = FakeConsole();
    final run = InstallRun(app: app(withChecksum: false), catalog: catalog, session: ConsoleSession(console));

    final done = run.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    run.cancel();
    await done;

    expect(run.error, contains('Cancelled'));
    expect(console.installs, isEmpty);
  });
}
