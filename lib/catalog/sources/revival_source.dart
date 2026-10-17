import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../catalog_client.dart';
import '../models.dart';
import 'store_source.dart';

const revivalBase = 'https://emulationrevival.github.io/';

const _pages = {
  'apps': 'App',
  'emulators': 'Emulator',
  'experimental-apps': 'Experimental',
  'frontends': 'Frontend',
  'media-apps': 'Media',
  'ports': 'Port',
  'utilities': 'Utility',
};

class RevivalSource extends StoreSource {
  const RevivalSource({this.base = revivalBase});

  final String base;

  @override
  String get id => 'revival';

  @override
  String get name => 'Emulation Revival';

  @override
  int get priority => 0;

  @override
  Future<CatalogLoad> load(FetchText fetch) async {
    final root = Uri.parse(base);
    final apps = <CatalogApp>[];
    final failed = <String>[];
    final pages = await Future.wait([
      for (final e in _pages.entries)
        () async {
          try {
            final url = root.resolve('xbox-dev-mode/${e.key}.html');
            return parseRevivalPage(await fetch(url), url, e.value);
          } catch (_) {
            failed.add(e.key);
            return <CatalogApp>[];
          }
        }(),
    ]);
    final seen = <String>{};
    for (final page in pages) {
      for (final app in page) {
        if (seen.add(app.slug)) apps.add(app);
      }
    }
    if (apps.isEmpty && failed.length == _pages.length) throw Exception('Emulation Revival could not be reached.');
    return CatalogLoad(apps, failed);
  }
}

List<CatalogApp> parseRevivalPage(String source, Uri page, String category) {
  final doc = html.parse(source);
  final out = <CatalogApp>[];
  for (final card in doc.querySelectorAll('div.card[id]')) {
    final modal = card.querySelector('.card-modal-content');
    final title = card.querySelector('.card-title')?.text.trim();
    if (modal == null || title == null || title.isEmpty) continue;

    final downloads = <CatalogDownload>[
      for (final a in modal.querySelectorAll('a.download-link'))
        if ((a.attributes['href'] ?? '').isNotEmpty)
          CatalogDownload(label: _labelFor(a.attributes['href']!, a.text.trim()), url: page.resolve(a.attributes['href']!).toString()),
    ];

    final img = card.querySelector('img.card-image')?.attributes['src'];
    final shown = modal.querySelector('.app-version .val')?.text.trim();
    final version = (shown != null && shown.isNotEmpty)
        ? shown
        : downloads.map((d) => versionFromUrl(d.url ?? '')).whereType<String>().firstOrNull;
    final description = card.querySelector('.card-description')?.text.trim() ?? '';

    out.add(CatalogApp(
      slug: card.id,
      base: page,
      name: title,
      summary: description,
      versionText: version ?? '',
      version: parseLooseVersion(version),
      updated: modal.querySelector('time.release-date')?.attributes['datetime'] ?? '',
      developer: _infoValue(modal, 'Developer'),
      category: category,
      compatibility: _compatibility(modal),
      cover: img == null ? null : page.resolve(img).toString(),
      about: '',
      aboutText: description,
      downloads: classifyDownloads(downloads, variants: true),
      source: modal.querySelector('a.source-code-link')?.attributes['href'] ?? '',
      package: null,
      sourceId: 'revival',
      sourceName: 'Emulation Revival',
    ));
  }
  return out;
}

String _labelFor(String href, String text) {
  final file = href.split('?').first.split('/').last.toLowerCase();
  return file.endsWith('.zip') || file.endsWith('.7z') ? 'Download archive' : (text.isEmpty ? 'Download' : text);
}

String _infoValue(Element modal, String label) {
  for (final li in modal.querySelectorAll('ul.info-list > li')) {
    final strong = li.querySelector('strong')?.text.trim() ?? '';
    if (strong.toLowerCase().startsWith(label.toLowerCase())) {
      final clone = li.clone(true);
      clone.querySelector('strong')?.remove();
      return clone.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
  }
  return '';
}

List<String> _compatibility(Element modal) {
  final text = _infoValue(modal, 'Compatibility');
  return [for (final p in text.split(RegExp(r'\s*[,|]\s*'))) if (p.isNotEmpty) p];
}
