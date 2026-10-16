import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../portal/portal_client.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'app_detail.dart';
import 'feedback.dart';
import 'install_page.dart';
import 'master_detail.dart';
import 'widgets.dart';

class InstalledPage extends StatefulWidget {
  const InstalledPage({super.key, required this.session, required this.catalog, required this.onOpenInStore});

  final ConsoleSession session;
  final CatalogStore catalog;
  final void Function(CatalogApp app) onOpenInStore;

  @override
  State<InstalledPage> createState() => _InstalledPageState();
}

class _InstalledPageState extends State<InstalledPage> {
  final _search = TextEditingController();
  String? _selected;

  ConsoleSession get s => widget.session;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(InstalledPackage p) {
    if (MasterDetail.isWide(context)) {
      setState(() => _selected = p.fullName);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AppDetailPage(session: s, catalog: widget.catalog, package: p, onOpenInStore: widget.onOpenInStore),
    ));
  }

  Future<void> _installFromFile() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstallPage(session: s)));
    if (mounted) attempt(context, s.refresh, address: s.address);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([s, widget.catalog, _search]),
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final all = s.visible;
        final matches = {for (final m in widget.catalog.matches(s.packages)) if (m.installed != null) m.installed!.fullName: m};
        bool hit(InstalledPackage p) => q.isEmpty || p.name.toLowerCase().contains(q) || p.familyName.toLowerCase().contains(q);

        final updates = [for (final p in all) if (hit(p) && matches[p.fullName]?.status == AppStatus.updateAvailable && matches[p.fullName]!.app.installable) p];
        final rest = [for (final p in all) if (hit(p) && !updates.contains(p)) p];
        final selected = s.packages.where((p) => p.fullName == _selected).firstOrNull;

        Widget row(InstalledPackage p, {bool update = false}) {
          final m = matches[p.fullName];
          final running = s.running.contains(p.fullName);
          return ListRow(
            leading: AppThumb(name: p.name, cover: m?.app.coverUri),
            title: p.name,
            subtitle: update ? '${p.version}  →  ${m!.app.versionText}' : '${p.version}',
            selected: selected?.fullName == p.fullName,
            trailing: update
                ? const StatusPill('Update', kind: PillKind.update)
                : running
                    ? const StatusPill('Running', kind: PillKind.running)
                    : null,
            onTap: () => _open(p),
          );
        }

        final master = RefreshIndicator(
          onRefresh: () => attempt(context, s.refresh, address: s.address),
          color: Brand.accent,
          backgroundColor: Brand.raised2,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Brand.s6),
            children: [
              PageHeader(
                title: 'Installed',
                subtitle: '${s.address}  ·  ${all.length} ${all.length == 1 ? 'app' : 'apps'}',
                trailing: PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  color: Brand.raised2,
                  onSelected: (v) {
                    if (v == 'file') _installFromFile();
                    if (v == 'refresh') attempt(context, s.refresh, address: s.address);
                    if (v == 'system') s.setShowSystemApps(!s.showSystemApps);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'file', child: Text('Install from a file')),
                    const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                    PopupMenuItem(value: 'system', child: Text(s.showSystemApps ? 'Hide console apps' : 'Show console apps')),
                  ],
                ),
              ),
              SearchField(controller: _search, hint: 'Search installed apps'),
              if (s.loading && s.packages.isEmpty) ...[for (var i = 0; i < 5; i++) const SkeletonRow()],
              if (!s.loading && all.isEmpty)
                SizedBox(
                  height: 320,
                  child: EmptyState(
                    title: 'Nothing installed yet',
                    body: 'Apps you add show up here. Pick one from the Store tab, or install a package file you already have.',
                    action: OutlinedButton(onPressed: _installFromFile, child: const Text('Install from a file')),
                  ),
                ),
              if (all.isNotEmpty && updates.isEmpty && rest.isEmpty)
                const Padding(padding: EdgeInsets.all(Brand.s5), child: Text('No installed app matches that search.')),
              if (updates.isNotEmpty) ...[
                SectionLabel('Updates', trailing: Text('${updates.length}', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Brand.accent))),
                for (final p in updates) row(p, update: true),
              ],
              if (rest.isNotEmpty) ...[
                if (updates.isNotEmpty) const SectionLabel('On this console'),
                for (final p in rest) row(p),
              ],
            ],
          ),
        );

        return MasterDetail(
          master: master,
          emptyHint: 'Select an app',
          detail: selected == null
              ? null
              : AppDetail(
                  key: ValueKey(selected.fullName),
                  session: s,
                  catalog: widget.catalog,
                  package: selected,
                  onGone: () => setState(() => _selected = null),
                  onOpenInStore: widget.onOpenInStore,
                ),
        );
      },
    );
  }
}
