import '../portal/models.dart';
import 'models.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

// finds the installed copy of a catalogue app. in order: a name the app learned when it installed
// this one, the package identity from project.json, then the display name
AppMatch matchApp(CatalogApp app, List<InstalledPackage> installed, {String? learnedName}) {
  InstalledPackage? hit;
  for (final identity in [learnedName, app.package]) {
    if (identity == null || identity.isEmpty) continue;
    final found = matchFamily(installed, identity);
    if (found.isNotEmpty) {
      hit = found.first;
      break;
    }
  }
  if (hit == null) {
    final want = _norm(app.name);
    final byName = [for (final p in installed) if (p.isDeveloper && _norm(p.name) == want) p]
      ..sort((a, b) => b.version.compareTo(a.version));
    if (byName.isNotEmpty) hit = byName.first;
  }
  if (hit == null) return AppMatch(app, null, AppStatus.notInstalled);

  final theirs = app.version;
  final status = theirs == null
      ? AppStatus.upToDate
      : switch (theirs.compareTo(hit.version)) {
          > 0 => AppStatus.updateAvailable,
          0 => AppStatus.upToDate,
          _ => AppStatus.newerThanCatalogue,
        };
  return AppMatch(app, hit, status);
}
