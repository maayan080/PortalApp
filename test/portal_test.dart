import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/portal/multipart.dart';
import 'package:portal_app/portal/portal_client.dart';

InstalledPackage pkg(String family, String version) {
  final v = PackageVersion.tryParse(version)!;
  return InstalledPackage(
    fullName: '${family}_${version}_x64__abc',
    familyName: family,
    relativeId: '${family}_abc!App',
    name: family,
    publisher: '',
    version: v,
    origin: 5,
    canUninstall: true,
    uninstallDeniedReason: '',
    listed: true,
    users: const [],
  );
}

void main() {
  test('versions sort numerically, not as text', () {
    final a = PackageVersion.tryParse('1.0.4.99')!;
    final b = PackageVersion.tryParse('1.0.4.351')!;
    expect(a.compareTo(b), lessThan(0));
    expect('1.0.4.99'.compareTo('1.0.4.351'), greaterThan(0));
  });

  test('bad version strings do not parse', () {
    expect(PackageVersion.tryParse('1.0.4'), isNull);
    expect(PackageVersion.tryParse('a.b.c.d'), isNull);
  });

  test('family match is by prefix and newest first', () {
    final all = [pkg('Acme.App', '1.0.4.99'), pkg('Acme.App', '1.0.4.351'), pkg('Other.App', '9.0.0.0')];
    final hits = matchFamily(all, 'Acme.App');
    expect(hits.map((p) => p.version.toString()), ['1.0.4.351', '1.0.4.99']);
  });

  test('family match takes the bare name the console sends, and a hashed one', () {
    InstalledPackage withFamily(String family, String version) => InstalledPackage(
          fullName: '${family}_${version}_x64__r9d4qta1rpjdr',
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
    final all = [
      withFamily('BanditVault.ADFYT', '1.0.1.0'),
      withFamily('BanditVault.ADFYT_r9d4qta1rpjdr', '1.0.0.9'),
      withFamily('BanditVault.ADFYTPro', '9.0.0.0'),
      withFamily('Other.App', '1.0.0.0'),
    ];
    // both identity spellings find both shapes, and a different app that starts the
    // same is left out
    for (final id in ['BanditVault.ADFYT', 'BanditVault.ADFYT_']) {
      expect(matchFamily(all, id).map((p) => p.version.toString()), ['1.0.1.0', '1.0.0.9']);
    }
  });

  test('package json maps across both size field names', () {
    expect(FileEntry.fromJson({'Name': 'a', 'Type': 16}, r'\').isDir, isTrue);
    expect(FileEntry.fromJson({'Name': 'a', 'FileSize': 5}, r'\').size, 5);
    expect(FileEntry.fromJson({'Name': 'a', 'SizeInBytes': 7}, r'\').size, 7);
  });

  test('names that are only punctuation fall back to the display name', () {
    final p = InstalledPackage.fromJson({'Name': '.', 'PackageDisplayName': 'ConsoleSupport', 'PackageFamilyName': 'XdashLauncher'});
    expect(p.name, 'ConsoleSupport');
    expect(InstalledPackage.fromJson({'Name': '...', 'PackageFamilyName': 'Fam'}).name, 'Fam');
  });

  test('multipart handles non-ascii and quoted file names', () async {
    final dir = await Directory.systemTemp.createTemp('portal_test');
    try {
      final f = File('${dir.path}/save (1) é 日本.bin')..writeAsBytesSync([1, 2, 3]);
      final body = MultipartBody([MultipartFile(f), MultipartFile(f, 'say "hi".bin')], boundary: 'xyz');
      final bytes = await body.stream().expand((c) => c).toList();
      expect(bytes.length, await body.length());
      final text = utf8.decode(bytes, allowMalformed: true);
      expect(text, contains('filename="save (1) é 日本.bin"'));
      expect(text, contains('filename="say %22hi%22.bin"'));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('multipart length matches the bytes streamed', () async {
    final dir = await Directory.systemTemp.createTemp('portal_test');
    try {
      final a = File('${dir.path}/one.appx')..writeAsBytesSync(List.generate(1000, (i) => i % 256));
      final b = File('${dir.path}/dep.appx')..writeAsBytesSync([1, 2, 3]);
      final body = MultipartBody([MultipartFile(a), MultipartFile(b)], boundary: 'xyz');
      final bytes = await body.stream().expand((c) => c).toList();
      expect(bytes.length, await body.length());
      final text = latin1.decode(bytes);
      expect(text, contains('name="one.appx"; filename="one.appx"'));
      expect(text, contains('name="dep.appx"; filename="dep.appx"'));
      expect(text.endsWith('--xyz--\r\n'), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
