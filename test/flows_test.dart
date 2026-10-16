import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/models.dart';
import 'package:portal_app/portal/portal_client.dart';
import 'package:portal_app/state/catalog_store.dart';
import 'package:portal_app/state/console_session.dart';
import 'package:portal_app/ui/shell.dart';

// the app as it really runs: the shell is pushed on top of the connect screen, which stays below it

Map<String, dynamic> pkgJson(String name, String family, String version, {bool listed = true}) {
  final v = version.split('.').map(int.parse).toList();
  return {
    'PackageFullName': '${family}_${version}_x64__abc',
    'PackageFamilyName': family,
    'PackageRelativeId': '${family}_abc!App',
    'Name': name,
    'Publisher': 'CN=BanditVault',
    'PackageOrigin': 5,
    'AppListEntry': listed ? 1 : 0,
    'CanUninstall': true,
    'Version': {'Major': v[0], 'Minor': v[1], 'Build': v[2], 'Revision': v[3]},
    'RegisteredUsers': [],
  };
}

List<int> appxBytes(String version) {
  final a = Archive();
  a.addFile(ArchiveFile.bytes(
      'AppxManifest.xml',
      utf8.encode('<Package><Identity Name="Acme.Widget" Publisher="CN=Acme" Version="$version" ProcessorArchitecture="x64"/>'
          '<Properties><DisplayName>Widget</DisplayName></Properties></Package>')));
  a.addFile(ArchiveFile.bytes('AppxSignature.p7x', [1]));
  return ZipEncoder().encode(a);
}

class FakeConsole extends PortalClient {
  FakeConsole(this.json) : super('10.0.0.1');

  List<Map<String, dynamic>> json;
  final calls = <String>[];
  bool failInstall = false;

  @override
  Future<List<InstalledPackage>> packages() async => [for (final j in json) InstalledPackage.fromJson(j)];

  @override
  Future<Set<String>> runningPackages() async => {};

  @override
  Future<void> launch(InstalledPackage p) async => calls.add('launch ${p.name}');

  @override
  Future<InstalledPackage> install(
    File package, {
    List<File> dependencies = const [],
    required String familyPrefix,
    String? expectedVersion,
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    calls.add('install ${package.uri.pathSegments.last}');
    if (failInstall) throw PortalException('The console refused it.');
    onUpload?.call(100, 100);
    json = [pkgJson('Widget', 'Acme.Widget', expectedVersion!)];
    return InstalledPackage.fromJson(json.first);
  }
}

class FakeCatalog extends CatalogClient {
  FakeCatalog() : super('https://example.com/');

  @override
  Future<String> about(CatalogApp app) async => 'About text.';

  @override
  Future<File> download(Uri uri, File dest, {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    await dest.writeAsBytes(appxBytes('1.0.0.4'));
    onProgress?.call(10, 10);
    return dest;
  }
}

CatalogApp storeApp(String slug, String name, String version) => CatalogApp.fromJson(slug, Uri.parse('https://example.com/projects/$slug/'), {
      'name': name,
      'summary': '$name does a useful thing.',
      'version': version,
      'updated': '2026-09-01',
      'category': 'Media app',
      'downloads': [
        {'label': 'Download APPX', 'file': '$slug.appx', 'size': '12 MB'},
      ],
    });

void main() {
  late FakeConsole console;
  late ConsoleSession session;
  late CatalogStore catalog;

  // connect screen below, shell on top, like the app
  Future<void> boot(WidgetTester tester, {bool wide = false}) async {
    tester.view.physicalSize = wide ? const Size(1200, 800) : const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = wide ? 1 : 3;
    addTearDown(tester.view.reset);

    console = FakeConsole([pkgJson('Widget', 'Acme.Widget', '1.0.0.3'), pkgJson('Gadget', 'Acme.Gadget', '2.0.0.0')]);
    session = ConsoleSession(console);
    await session.refresh();
    catalog = CatalogStore(clientFactory: (_) => FakeCatalog());
    catalog.apps = [storeApp('widget', 'Widget', '1.0.0.4'), storeApp('gadget', 'Gadget', '2.0.0.0')];
    catalog.loaded = true;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (c) => Shell(session: session, catalog: catalog, onDisconnect: () => Navigator.of(c).pop()),
              )),
              child: const Text('Connect'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
  }

  // the install screen chains real file reads, so alternate real time with pumps until it shows up
  Future<void> until(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final wide in [false, true]) {
    final where = wide ? 'desktop' : 'phone';

    testWidgets('$where: View in store from an app goes to the store, and stays connected', (tester) async {
      await boot(tester, wide: wide);
      await tester.tap(find.text('Gadget'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.textContaining('Raccoon Dev Store lists'));
      await tester.tap(find.textContaining('Raccoon Dev Store lists'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // still on the shell, not thrown back to the connect screen
      expect(find.text('Connect'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Reinstall'), findsOneWidget);
    });

    testWidgets('$where: update from the store, then Done', (tester) async {
      await boot(tester, wide: wide);
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'));
      await tester.pump();
      await until(tester, find.widgetWithText(FilledButton, 'Done'));
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Installing'), findsNothing);
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('$where: update from the store, then Open on console', (tester) async {
      await boot(tester, wide: wide);
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'));
      await tester.pump();
      await until(tester, find.widgetWithText(OutlinedButton, 'Open on console'));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Open on console'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(console.calls, contains('launch Widget'));
      expect(find.text('Installing'), findsNothing);
    });

    testWidgets('$where: a failed install, Try again and Close', (tester) async {
      await boot(tester, wide: wide);
      console.failInstall = true;
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'));
      await tester.pump();
      await until(tester, find.text('Try again'));
      expect(find.text('The console refused it.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      await until(tester, find.text('Try again'));
      expect(tester.takeException(), isNull);
      expect(find.text('The console refused it.'), findsOneWidget);
      expect(console.calls.where((c) => c.startsWith('install')), hasLength(2));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Installing'), findsNothing);
    });

    testWidgets('$where: update from an installed app, then Done', (tester) async {
      await boot(tester, wide: wide);
      await tester.tap(find.text('Widget'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Update to 1.0.0.4'));
      await tester.pump();
      await until(tester, find.widgetWithText(FilledButton, 'Done'));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Connect'), findsNothing);
    });
  }
}
