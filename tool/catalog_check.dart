// reads the live catalogue and, with a console address, matches it against what is installed.
//   dart run tool/catalog_check.dart [console address] [--download <slug>]
// it never installs anything. --download fetches the package to a temp folder and checks it.
import 'dart:io';

import 'package:portal_app/catalog/catalog_client.dart';
import 'package:portal_app/catalog/matching.dart';
import 'package:portal_app/portal/package_info.dart';
import 'package:portal_app/portal/portal_client.dart';

Future<void> main(List<String> args) async {
  final slug = args.contains('--download') ? args[args.indexOf('--download') + 1] : null;
  final address = args.where((a) => !a.startsWith('--') && a != slug).firstOrNull;

  final catalog = CatalogClient(defaultCatalogueUrl);
  final load = await catalog.load();
  stdout.writeln('${load.apps.length} apps, ${load.failed.length} failed to load');
  for (final a in load.apps) {
    stdout.writeln('\n${a.name}  v${a.versionText}  [${a.category}]  cover=${a.coverUri}');
    for (final d in a.downloads) {
      stdout.writeln('  ${d.role.name.padRight(10)} ${d.name}  ${d.size ?? ''}  -> ${a.resolve(d)}');
    }
    stdout.writeln('  installable=${a.installable} deps=${a.dependencies.map((d) => d.name).join(', ')} checksum=${a.checksum?.name}');
    if (a.checksum != null) stdout.writeln('  published sha256: ${await catalog.checksumFor(a, a.checksum!)}');
    final about = await catalog.about(a);
    stdout.writeln('  about: ${about.split('\n').first}');
  }

  if (address != null) {
    final portal = PortalClient(address);
    try {
      await portal.connect();
      final installed = await portal.packages();
      stdout.writeln('\n== against $address (${installed.length} packages)');
      for (final a in load.apps) {
        final m = matchApp(a, installed);
        stdout.writeln('${a.name}: ${m.status.name}${m.installed == null ? '' : ' (console has ${m.installed!.version}, store ${a.versionText})'}');
      }
    } finally {
      portal.close();
    }
  }

  if (slug != null) {
    final app = load.apps.firstWhere((a) => a.slug == slug);
    final dir = await Directory.systemTemp.createTemp('catalog_check');
    try {
      final main = app.mainPackage!;
      final file = await catalog.download(app.resolve(main), File('${dir.path}/${main.name}'),
          onProgress: (got, total) => stdout.write('\r  ${got ~/ 1024} of ${total ~/ 1024} KB'));
      stdout.writeln();
      final info = await readPackageInfo(file);
      stdout.writeln('package: ${info.displayName} ${info.version} signed=${info.signed} identity=${info.name}');
      final sum = app.checksum;
      if (sum != null) {
        final expected = await catalog.checksumFor(app, sum);
        final actual = await sha256Of(file);
        stdout.writeln('checksum ${expected == actual ? 'MATCHES' : 'DIFFERS'}  $actual');
      }
    } finally {
      await dir.delete(recursive: true);
    }
  }
}
