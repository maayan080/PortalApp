import 'dart:io';

import 'package:flutter/foundation.dart';

import '../portal/package_info.dart';
import '../portal/portal_client.dart';

class ConsoleSession extends ChangeNotifier {
  ConsoleSession(this.client);

  final PortalClient client;

  List<InstalledPackage> packages = [];
  Set<String> running = {};
  bool loading = false;

  // microsoft's own apps are hidden from the lists unless this is on
  bool showSystemApps = false;

  void setShowSystemApps(bool v) {
    showSystemApps = v;
    notifyListeners();
  }

  List<InstalledPackage> get visible => [for (final p in packages) if (showSystemApps || p.isDeveloper) p];

  // full names of packages with an action in flight
  final Set<String> busy = {};

  String get address => client.address;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final list = await client.packages();
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      packages = list;
      // the process list is a nicety, the app list still works without it
      try {
        running = await client.runningPackages();
      } catch (_) {
        running = {};
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _act(InstalledPackage p, Future<void> Function() action) async {
    busy.add(p.fullName);
    notifyListeners();
    try {
      await action();
    } finally {
      busy.remove(p.fullName);
      notifyListeners();
    }
  }

  // installs or updates in place, then refreshes the list
  Future<InstalledPackage> install(
    PackageInfo info, {
    List<File> dependencies = const [],
    Progress? onUpload,
    void Function(InstallState)? onState,
  }) async {
    final p = await client.install(info.file,
        dependencies: dependencies,
        familyPrefix: info.familyPrefix,
        expectedVersion: info.version.toString(),
        onUpload: onUpload,
        onState: onState);
    await refresh();
    return p;
  }

  Future<void> launch(InstalledPackage p) => _act(p, () async {
        await client.launch(p);
        running = {...running, p.fullName};
      });

  // returns false when the portal refused, usually because it was not running
  Future<bool> close(InstalledPackage p) async {
    var closed = false;
    await _act(p, () async {
      closed = await client.closeApp(p);
      if (closed) running = {...running}..remove(p.fullName);
    });
    return closed;
  }

  Future<void> delete(InstalledPackage p) => _act(p, () async {
        await client.uninstall(p);
        packages = packages.where((e) => e.fullName != p.fullName).toList();
        running = {...running}..remove(p.fullName);
      });

  @override
  void dispose() {
    client.close();
    super.dispose();
  }
}
