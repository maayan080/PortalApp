import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog/catalog_client.dart';
import '../catalog/matching.dart';
import '../catalog/models.dart';
import '../catalog/sources/devstore_source.dart';
import '../catalog/sources/merge.dart';
import '../catalog/sources/raccoon_source.dart';
import '../catalog/sources/revival_source.dart';
import '../catalog/sources/store_source.dart';
import '../portal/models.dart';
import '../portal/package_info.dart';

class CatalogStore extends ChangeNotifier {
  CatalogStore({String? url, CatalogClient Function(String url)? clientFactory, List<StoreSource>? extraSources})
      : _url = url ?? defaultCatalogueUrl,
        _factory = clientFactory ?? CatalogClient.new,
        _extra = extraSources ?? (clientFactory == null ? const [RevivalSource(), DevStoreSource()] : const []);

  final List<StoreSource> _extra;

  Map<String, String> sourceErrors = {};

  final CatalogClient Function(String url) _factory;

  static const _urlKey = 'catalogue_url';
  static const _learnedKey = 'catalogue_learned';

  String _url;
  List<CatalogApp> apps = [];
  List<String> failed = [];
  bool loading = false;
  bool loaded = false;
  String? error;

  // slug to the package identity name it installed as, so updates are found without guessing
  Map<String, String> _learned = {};

  String get url => _url;
  CatalogClient get client => _factory(_url);

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _url = prefs.getString(_urlKey) ?? _url;
      final raw = prefs.getString(_learnedKey);
      if (raw != null) _learned = (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {}
  }

  Future<void> load() async {
    loading = true;
    error = null;
    sourceErrors = {};
    notifyListeners();
    try {
      final c = client;
      final sources = [RaccoonSource(c), ..._extra]..sort((a, b) => a.priority.compareTo(b.priority));
      final results = await Future.wait([
        for (final src in sources)
          src.load(c.text).then<CatalogLoad?>((r) => r).catchError((Object e) {
            sourceErrors[src.name] = e is PortalException ? e.message : friendlyCatalogueError(e);
            return null;
          }),
      ]);
      final good = [for (final r in results) if (r != null) r];
      if (good.isEmpty) throw PortalException(sourceErrors.values.first);
      apps = [for (final a in mergeApps([for (final r in good) r.apps])) a.copyWith(category: normalizeCategory(a.category))];
      failed = [for (final r in good) ...r.failed];
      loaded = true;
    } catch (e) {
      error = e is PortalException ? e.message : friendlyCatalogueError(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> setUrl(String value) async {
    final v = value.trim().isEmpty ? defaultCatalogueUrl : value.trim();
    _url = v.endsWith('/') ? v : '$v/';
    apps = [];
    loaded = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_url == defaultCatalogueUrl) {
        await prefs.remove(_urlKey);
      } else {
        await prefs.setString(_urlKey, _url);
      }
    } catch (_) {}
    await load();
  }

  void learn(CatalogApp app, PackageInfo info) {
    _learned[app.slug] = info.name;
    notifyListeners();
    SharedPreferences.getInstance().then((p) => p.setString(_learnedKey, jsonEncode(_learned))).catchError((_) => false);
  }

  AppMatch matchFor(CatalogApp app, List<InstalledPackage> installed) =>
      matchApp(app, installed, learnedName: _learned[app.slug]);

  List<AppMatch> matches(List<InstalledPackage> installed) => [for (final a in apps) matchFor(a, installed)];

  AppMatch? forInstalled(InstalledPackage p, List<InstalledPackage> installed) {
    for (final a in apps) {
      final m = matchFor(a, installed);
      if (m.installed?.fullName == p.fullName) return m;
    }
    return null;
  }
}

String friendlyCatalogueError(Object e) =>
    'The store could not be reached. Check this device is online, then try again.';
