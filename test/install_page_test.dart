import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/portal/portal_client.dart';
import 'package:portal_app/state/console_session.dart';
import 'package:portal_app/ui/install_page.dart';

class FakeClient extends PortalClient {
  FakeClient(this.have) : super('10.0.0.1');

  List<InstalledPackage> have;
  final calls = <String>[];

  @override
  Future<List<InstalledPackage>> packages() async => have;

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
    calls.add('install ${package.uri.pathSegments.last} $expectedVersion deps=${dependencies.length}');
    onUpload?.call(50, 100);
    onUpload?.call(100, 100);
    final p = InstalledPackage(
      fullName: 'Acme.Widget_${expectedVersion}_x64__abc',
      familyName: 'Acme.Widget',
      relativeId: '',
      name: 'Widget',
      publisher: '',
      version: PackageVersion.tryParse(expectedVersion!)!,
      origin: 5,
      canUninstall: true,
      uninstallDeniedReason: '',
      listed: true,
      users: const [],
    );
    have = [p];
    return p;
  }
}

Future<File> makeAppx(Directory dir, String version, {bool signed = true}) async {
  final a = Archive();
  a.addFile(ArchiveFile.bytes(
      'AppxManifest.xml',
      utf8.encode('<Package><Identity Name="Acme.Widget" Publisher="CN=Acme" Version="$version" ProcessorArchitecture="x64"/>'
          '<Properties><DisplayName>Widget</DisplayName></Properties></Package>')));
  if (signed) a.addFile(ArchiveFile.bytes('AppxSignature.p7x', [1]));
  final f = File('${dir.path}/widget_$version.appx');
  await f.writeAsBytes(ZipEncoder().encode(a));
  return f;
}

InstalledPackage installed(String version) => InstalledPackage(
      fullName: 'Acme.Widget_${version}_x64__abc',
      familyName: 'Acme.Widget',
      relativeId: '',
      name: 'Widget',
      publisher: '',
      version: PackageVersion.tryParse(version)!,
      origin: 5,
      canUninstall: true,
      uninstallDeniedReason: '',
      listed: true,
      users: const [],
    );

// the page chains several real file reads, so alternate real time with pumps
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('installpage'));
  tearDown(() => dir.delete(recursive: true));

  Future<FakeClient> open(WidgetTester tester, File file, List<InstalledPackage> have) async {
    final client = FakeClient(have);
    final session = ConsoleSession(client);
    await session.refresh();
    await tester.pumpWidget(MaterialApp(
      home: InstallPage(session: session, pick: ({required multiple}) async => [file]),
    ));
    return client;
  }

  testWidgets('update flow shows the plan, installs and finishes', (tester) async {
    final file = await tester.runAsync(() => makeAppx(dir, '1.2.3.4'));
    final client = (await tester.runAsync(() => open(tester, file!, [installed('1.2.3.3')])))!;

    await tester.tap(find.text('Choose package'));
    await settle(tester);
    expect(find.textContaining('Update from 1.2.3.3 to 1.2.3.4'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await settle(tester);
    expect(client.calls, ['install widget_1.2.3.4.appx 1.2.3.4 deps=0']);
    expect(find.text('Widget 1.2.3.4 is installed.'), findsOneWidget);
  });

  testWidgets('an unsigned package cannot be installed', (tester) async {
    final file = await tester.runAsync(() => makeAppx(dir, '1.0.0.0', signed: false));
    await tester.runAsync(() => open(tester, file!, []));

    await tester.tap(find.text('Choose package'));
    await settle(tester);
    expect(find.textContaining('not signed'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Install')).onPressed, isNull);
  });

  testWidgets('a file that is not a package shows an error', (tester) async {
    final junk = File('${dir.path}/junk.appx')..writeAsStringSync('nope');
    await tester.runAsync(() => open(tester, junk, []));

    await tester.tap(find.text('Choose package'));
    await settle(tester);
    expect(find.textContaining('not an app package'), findsOneWidget);
  });
}
