import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../portal/portal_client.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'feedback.dart';
import 'files_page.dart';
import 'store_install_page.dart';
import 'widgets.dart';

// phone pushes this as a page, desktop shows it beside the list
class AppDetail extends StatelessWidget {
  const AppDetail({
    super.key,
    required this.session,
    required this.catalog,
    required this.package,
    this.onGone,
    this.onOpenInStore,
  });

  final ConsoleSession session;
  final CatalogStore catalog;
  final InstalledPackage package;

  // called after the app is deleted, so the page can leave
  final VoidCallback? onGone;
  final void Function(CatalogApp app)? onOpenInStore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, catalog]),
      builder: (context, _) {
        final text = Theme.of(context).textTheme;
        final p = session.packages.where((e) => e.fullName == package.fullName).firstOrNull ?? package;
        final match = catalog.forInstalled(p, session.packages);
        final running = session.running.contains(p.fullName);
        final busy = session.busy.contains(p.fullName);
        final update = match != null && match.status == AppStatus.updateAvailable && match.app.installable;
        final address = session.address;

        Widget launchOrClose({required bool primary}) {
          if (running) {
            final label = busy ? 'Closing' : 'Close';
            final onTap = busy ? null : () async {
              final closed = await session.close(p);
              if (context.mounted) say(context, closed ? '${p.name} closed' : '${p.name} is not running');
            };
            return primary ? FilledButton(onPressed: onTap, child: Text(label)) : OutlinedButton(onPressed: onTap, child: Text(label));
          }
          final onTap = !p.listed || busy ? null : () => attempt(context, () => session.launch(p), address: address);
          final label = busy ? 'Launching' : 'Launch';
          return primary ? FilledButton(onPressed: onTap, child: Text(label)) : OutlinedButton(onPressed: onTap, child: Text(label));
        }

        return ListView(
          padding: const EdgeInsets.all(Brand.s4),
          children: [
            Row(children: [
              AppThumb(name: p.name, cover: match?.app.coverUri, size: 72),
              const SizedBox(width: Brand.s4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.name, style: text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${p.version}  ·  ${shortPublisher(p.publisher)}', style: text.bodySmall?.copyWith(fontSize: 13)),
                  const SizedBox(height: Brand.s2),
                  Wrap(spacing: Brand.s2, runSpacing: Brand.s2, children: [
                    if (running) const StatusPill('Running', kind: PillKind.running),
                    if (update) StatusPill('${match.app.versionText} available', kind: PillKind.update),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: Brand.s5),
            if (update) ...[
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final done = await startStoreInstall(context, session, catalog, match.app);
                        if (done) await session.refresh();
                      },
                child: Text('Update to ${match.app.versionText}'),
              ),
              const SizedBox(height: Brand.s3),
              Row(children: [
                Expanded(child: launchOrClose(primary: false)),
                const SizedBox(width: Brand.s3),
                Expanded(child: _filesButton(context, p)),
              ]),
            ] else if (!p.listed) ...[
              // nothing to launch, so the files are the main thing to do here
              _filesButton(context, p, primary: true),
            ] else ...[
              launchOrClose(primary: true),
              const SizedBox(height: Brand.s3),
              _filesButton(context, p),
            ],
            if (!p.listed)
              Padding(
                padding: const EdgeInsets.only(top: Brand.s3),
                child: Text('The console lists no app to start in this package, so it cannot be launched from here.', style: text.bodySmall?.copyWith(fontSize: 13)),
              ),
            if (match != null && onOpenInStore != null) ...[
              const SectionLabel('In the store'),
              ListRow(
                title: 'Raccoon Dev Store lists ${match.app.versionText}',
                subtitle: match.status == AppStatus.updateAvailable
                    ? 'Newer than the ${p.version} on your console'
                    : match.status == AppStatus.newerThanCatalogue
                        ? 'Your console has a newer build than the store'
                        : 'Matches the version on your console',
                trailing: const Icon(Icons.chevron_right, color: Brand.faint),
                onTap: () => onOpenInStore!(match.app),
              ),
            ],
            const SectionLabel('Details'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Brand.s4),
              child: Column(children: [
                FactRow('Package', p.familyName),
                FactRow('Full name', p.fullName),
                FactRow('Publisher', p.publisher),
                if (p.users.isNotEmpty) FactRow('Registered for', p.users.join(', ')),
              ]),
            ),
            if (p.canUninstall) ...[
              const SizedBox(height: Brand.s6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  style: TextButton.styleFrom(foregroundColor: Brand.error),
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await confirmDelete(context, p) || !context.mounted) return;
                          final ok = await attempt(context, () => session.delete(p), done: '${p.name} deleted', address: address);
                          if (ok) onGone?.call();
                        },
                  child: const Text('Delete from console'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: Brand.s5),
                child: Text(p.uninstallDeniedReason.isEmpty ? 'The console does not allow this app to be removed.' : p.uninstallDeniedReason,
                    style: text.bodySmall?.copyWith(fontSize: 13)),
              ),
          ],
        );
      },
    );
  }

  Widget _filesButton(BuildContext context, InstalledPackage p, {bool primary = false}) {
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FilesPage(session: session, package: p)));
    return primary ? FilledButton(onPressed: open, child: const Text('Files')) : OutlinedButton(onPressed: open, child: const Text('Files'));
  }
}

// the phone version, the same view as a page of its own
class AppDetailPage extends StatelessWidget {
  const AppDetailPage({super.key, required this.session, required this.catalog, required this.package, this.onOpenInStore});

  final ConsoleSession session;
  final CatalogStore catalog;
  final InstalledPackage package;
  final void Function(CatalogApp app)? onOpenInStore;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: AppDetail(
            session: session,
            catalog: catalog,
            package: package,
            onGone: () => Navigator.of(context).pop(),
            onOpenInStore: onOpenInStore,
          ),
        ),
      ),
    );
  }
}
