import 'package:flutter_test/flutter_test.dart';
import 'package:portal_app/main.dart';
import 'package:portal_app/state/catalog_store.dart';
import 'package:portal_app/state/recent_consoles.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('connect page asks for an address', (tester) async {
    await tester.pumpWidget(PortalApp(catalog: CatalogStore()));
    await tester.pump();
    expect(find.text('Console address'), findsOneWidget);

    await tester.tap(find.text('Connect'));
    await tester.pump();
    expect(find.textContaining('Enter the console address'), findsOneWidget);
  });

  test('recent consoles keep newest first and one per address', () async {
    final r = RecentConsoles();
    await r.remember(const SavedConsole('192.168.1.5'));
    await r.remember(const SavedConsole('192.168.1.9'));
    final list = await r.remember(const SavedConsole('192.168.1.5', username: 'player'));
    expect(list.map((c) => c.address), ['192.168.1.5', '192.168.1.9']);
    expect(list.first.username, 'player');
    expect((await r.forget(list.first)).map((c) => c.address), ['192.168.1.9']);
  });
}
