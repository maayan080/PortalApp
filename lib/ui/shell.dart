import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../theme/brand.dart';
import 'console_page.dart';
import 'installed_page.dart';
import 'store_page.dart';

// bottom bar on a phone, rail on a wide screen
class Shell extends StatefulWidget {
  const Shell({super.key, required this.session, required this.catalog, required this.onDisconnect});

  final ConsoleSession session;
  final CatalogStore catalog;
  final VoidCallback onDisconnect;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  final _storeFocus = ValueNotifier<CatalogApp?>(null);

  @override
  void initState() {
    super.initState();
    if (!widget.catalog.loaded && !widget.catalog.loading) widget.catalog.load();
  }

  @override
  void dispose() {
    _storeFocus.dispose();
    super.dispose();
  }

  void _openInStore(CatalogApp app) {
    // a detail page pushed on a phone sits above the shell, so close back to the shell. not to the
    // first route, that is the connect screen below it and popping there would disconnect
    final shellRoute = ModalRoute.of(context);
    Navigator.of(context).popUntil((r) => r == shellRoute);
    setState(() => _index = 1);
    _storeFocus.value = app;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final pages = [
      InstalledPage(session: widget.session, catalog: widget.catalog, onOpenInStore: _openInStore),
      StorePage(session: widget.session, catalog: widget.catalog, focus: _storeFocus),
      ConsolePage(session: widget.session, catalog: widget.catalog, onDisconnect: widget.onDisconnect),
    ];

    return ListenableBuilder(
      listenable: Listenable.merge([widget.session, widget.catalog]),
      builder: (context, _) {
        final updates = widget.catalog
            .matches(widget.session.packages)
            .where((m) => m.status == AppStatus.updateAvailable && m.app.installable)
            .length;

        Widget installedIcon(bool selected) => Badge(
              isLabelVisible: updates > 0,
              label: Text('$updates'),
              backgroundColor: Brand.accent,
              textColor: Brand.accentInk,
              child: Icon(selected ? Icons.apps : Icons.apps_outlined),
            );

        final body = IndexedStack(index: _index, children: pages);

        if (wide) {
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                leading: Padding(padding: const EdgeInsets.symmetric(vertical: Brand.s4), child: Image.asset('assets/logo.png', width: 36, height: 36)),
                destinations: [
                  NavigationRailDestination(icon: installedIcon(false), selectedIcon: installedIcon(true), label: const Text('Installed')),
                  const NavigationRailDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: Text('Store')),
                  const NavigationRailDestination(icon: Icon(Icons.tv_outlined), selectedIcon: Icon(Icons.tv), label: Text('Console')),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          body: SafeArea(bottom: false, child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              NavigationDestination(icon: installedIcon(false), selectedIcon: installedIcon(true), label: 'Installed'),
              const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Store'),
              const NavigationDestination(icon: Icon(Icons.tv_outlined), selectedIcon: Icon(Icons.tv), label: 'Console'),
            ],
          ),
        );
      },
    );
  }
}
