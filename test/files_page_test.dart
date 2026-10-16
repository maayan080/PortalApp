import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/portal/portal_client.dart';
import 'package:portal_app/state/console_session.dart';
import 'package:portal_app/ui/file_host.dart';
import 'package:portal_app/ui/files_page.dart';

InstalledPackage pkg() => const InstalledPackage(
      fullName: 'Acme.Widget_1.0.0.0_x64__abc',
      familyName: 'Acme.Widget',
      relativeId: 'Acme.Widget_abc!App',
      name: 'Widget',
      publisher: '',
      version: PackageVersion(1, 0, 0, 0),
      origin: 5,
      canUninstall: true,
      uninstallDeniedReason: '',
      listed: true,
      users: [],
    );

FileEntry dir(String name, String path) => FileEntry(name: name, isDir: true, size: null, path: path);
FileEntry file(String name, String path, int size) => FileEntry(name: name, isDir: false, size: size, path: path);

// a console with a small data tree, answered from memory
class FakeClient extends PortalClient {
  FakeClient(this.tree) : super('10.0.0.1');

  final Map<String, List<FileEntry>> tree;
  final calls = <String>[];
  bool refuseFolders = false;

  @override
  Future<List<FileEntry>> listFiles(InstalledPackage p, {String path = r'\LocalState'}) async {
    calls.add('list $path');
    final items = tree[path];
    if (items == null) throw PortalException('no such folder', status: 404);
    return List.of(items);
  }

  @override
  Future<File> download(InstalledPackage p, String name, File dest, {String path = r'\LocalState', Progress? onProgress}) async {
    calls.add('download $path $name');
    onProgress?.call(5, 10);
    await dest.writeAsString('contents of $name');
    return dest;
  }

  @override
  Future<void> upload(InstalledPackage p, File f, {String path = r'\LocalState', Progress? onProgress}) async {
    final name = f.uri.pathSegments.last;
    calls.add('upload $path $name');
    onProgress?.call(1, 1);
    tree[path]!.add(file(name, path, await f.length()));
  }

  @override
  Future<void> deleteFile(InstalledPackage p, String name, {String path = r'\LocalState'}) async {
    calls.add('delete $path $name');
    tree[path]!.removeWhere((e) => e.name == name);
  }

  @override
  Future<void> makeFolder(InstalledPackage p, String parent, String name) async {
    calls.add('mkdir $parent $name');
    if (refuseFolders) return;
    tree[parent]!.add(dir(name, parent));
    tree[parent == r'\' ? '\\$name' : '$parent\\$name'] = [];
  }
}

class FakeHost implements FileHost {
  FakeHost(this.dir, {this.uploads = const []});

  final Directory dir;
  final List<File> uploads;
  final messages = <String>[];

  @override
  Future<List<File>> pickUploads() async => uploads;

  @override
  Future<File?> downloadTarget(String name) async => File('${dir.path}/$name');

  @override
  Future<String> finished(File saved) async {
    messages.add(saved.path);
    return 'Saved to ${saved.path}';
  }
}

Map<String, List<FileEntry>> sampleTree() => {
      r'\': [dir('LocalState', r'\'), dir('TempState', r'\')],
      r'\LocalState': [file('b.log', r'\LocalState', 2048), dir('saves', r'\LocalState'), file('a.txt', r'\LocalState', 12)],
      r'\LocalState\saves': [file('slot1.sav', r'\LocalState\saves', 5 * 1024 * 1024)],
      r'\TempState': [],
    };

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('filespage'));
  tearDown(() => tmp.delete(recursive: true));

  Future<(FakeClient, FakeHost)> open(WidgetTester tester, {Map<String, List<FileEntry>>? tree, List<File> uploads = const []}) async {
    final client = FakeClient(tree ?? sampleTree());
    final host = FakeHost(tmp, uploads: uploads);
    await tester.pumpWidget(MaterialApp(home: FilesPage(session: ConsoleSession(client), package: pkg(), host: host)));
    await tester.pump();
    return (client, host);
  }

  testWidgets('shows folders first and opens them, back climbs out', (tester) async {
    final (client, _) = await open(tester);
    expect(find.text('LocalState'), findsOneWidget);

    await tester.tap(find.text('LocalState'));
    await tester.pumpAndSettle();
    expect(client.calls.last, r'list \LocalState');
    // folder first, then files by name
    final saves = tester.getTopLeft(find.text('saves')).dy;
    expect(saves, lessThan(tester.getTopLeft(find.text('a.txt')).dy));
    expect(tester.getTopLeft(find.text('a.txt')).dy, lessThan(tester.getTopLeft(find.text('b.log')).dy));
    expect(find.text('2.0 KB'), findsOneWidget);

    await tester.tap(find.text('saves'));
    await tester.pumpAndSettle();
    expect(find.text(r'\LocalState\saves'), findsOneWidget);
    expect(find.text('5.0 MB'), findsOneWidget);

    // back goes up one folder at a time, staying on the page
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('b.log'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('TempState'), findsOneWidget);
    expect(find.byType(FilesPage), findsOneWidget);
  });

  testWidgets('an app with no data says so', (tester) async {
    await open(tester, tree: {r'\': []});
    expect(find.textContaining('not created any data yet'), findsOneWidget);
  });

  testWidgets('download writes the file where the host says', (tester) async {
    final (client, host) = await open(tester);
    await tester.tap(find.text('LocalState'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Download').first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(client.calls.last, r'download \LocalState a.txt');
    expect(host.messages.single, endsWith('a.txt'));
    expect(File('${tmp.path}/a.txt').readAsStringSync(), 'contents of a.txt');
  });

  testWidgets('upload sends each chosen file and lists it', (tester) async {
    final f1 = File('${tmp.path}/new1.bin')..writeAsBytesSync([1, 2, 3]);
    final f2 = File('${tmp.path}/new2.bin')..writeAsBytesSync([4, 5]);
    final (client, _) = await open(tester, uploads: [f1, f2]);
    await tester.tap(find.text('LocalState'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Upload files'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(client.calls.where((c) => c.startsWith('upload')), [r'upload \LocalState new1.bin', r'upload \LocalState new2.bin']);
    expect(find.text('new1.bin'), findsOneWidget);
    expect(find.text('new2.bin'), findsOneWidget);
  });

  testWidgets('delete asks first', (tester) async {
    final (client, _) = await open(tester);
    await tester.tap(find.text('LocalState'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.calls.any((c) => c.startsWith('delete')), isFalse);

    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(client.calls, contains(r'delete \LocalState a.txt'));
    expect(find.text('a.txt'), findsNothing);
  });

  testWidgets('new folder appears, and a refused one is reported', (tester) async {
    final (client, _) = await open(tester);
    await tester.tap(find.text('LocalState'));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.create_new_folder_outlined)).onPressed, isNotNull);

    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'logs');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(client.calls, contains(r'mkdir \LocalState logs'));
    expect(find.text('logs'), findsOneWidget);

    client.refuseFolders = true;
    await tester.tap(find.byTooltip('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.textContaining('would not create "nope"'), findsOneWidget);
  });

  testWidgets('no new folder at the data root', (tester) async {
    await open(tester);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.create_new_folder_outlined)).onPressed, isNull);
  });
}
