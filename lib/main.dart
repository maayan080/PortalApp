import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/catalog_store.dart';
import 'theme/brand.dart';
import 'ui/connect_page.dart';

Future<void> main() => startApp();

// split from main so a test build can add its own actions to the connect screen
Future<void> startApp({ConnectExtras? extras}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // the font is bundled under its own licence, so list it with the others
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Karla'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  final catalog = CatalogStore();
  await catalog.restore();
  // start reading the store now, it is ready by the time a console is connected
  catalog.load();
  runApp(PortalApp(catalog: catalog, extras: extras));
}

class PortalApp extends StatelessWidget {
  const PortalApp({super.key, required this.catalog, this.extras});

  final CatalogStore catalog;
  final ConnectExtras? extras;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PortalApp',
      debugShowCheckedModeBanner: false,
      theme: Brand.theme(),
      themeMode: ThemeMode.dark,
      darkTheme: Brand.theme(),
      home: ConnectPage(catalog: catalog, extras: extras),
    );
  }
}
