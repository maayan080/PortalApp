import 'package:flutter/material.dart';

import '../portal/portal_client.dart';
import '../state/catalog_store.dart';
import '../state/console_session.dart';
import '../state/recent_consoles.dart';
import '../theme/brand.dart';
import 'errors.dart';
import 'shell.dart';
import 'widgets.dart';

// extra ways in, drawn below Connect. openWith starts the app on any console client
typedef ConnectExtras = Widget Function(BuildContext context, bool busy, Future<void> Function(PortalClient client) openWith);

class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.catalog, this.recents, this.extras});

  final CatalogStore catalog;
  final ConnectExtras? extras;

  // swapped out in tests
  final RecentConsoles? recents;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final RecentConsoles _recents = widget.recents ?? RecentConsoles();
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  List<SavedConsole> _saved = [];
  bool _busy = false;
  bool _signIn = false;
  String? _error;
  String _step = '';

  @override
  void initState() {
    super.initState();
    _recents.load().then((list) {
      if (!mounted) return;
      setState(() => _saved = list);
      if (list.isNotEmpty && _address.text.isEmpty) _fill(list.first);
    });
  }

  @override
  void dispose() {
    _address.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _fill(SavedConsole c) {
    _address.text = c.port == 11443 ? c.address : '${c.address}:${c.port}';
    _user.text = c.username ?? '';
    _pass.clear();
    setState(() => _signIn = c.username != null);
  }

  // accepts 192.168.1.5 or 192.168.1.5:11443
  (String, int)? _parse(String text) {
    final t = text.trim().replaceFirst(RegExp(r'^https?://'), '').replaceAll(RegExp(r'/+$'), '');
    if (t.isEmpty) return null;
    final i = t.lastIndexOf(':');
    if (i < 0) return (t, 11443);
    final port = int.tryParse(t.substring(i + 1));
    if (port == null || port < 1 || port > 65535) return null;
    return (t.substring(0, i), port);
  }

  Future<void> _connect() async {
    final target = _parse(_address.text);
    if (target == null) {
      setState(() => _error = 'Enter the console address, like 192.168.1.20');
      return;
    }
    final (address, port) = target;
    final user = _signIn && _user.text.trim().isNotEmpty ? _user.text.trim() : null;
    setState(() {
      _busy = true;
      _error = null;
      _step = 'Reaching $address';
    });

    final client = PortalClient(address, port: port, username: user, password: user == null ? null : _pass.text);
    try {
      if (!await PortalClient.reachable(address, port: port)) {
        throw PortalException('Nothing answered at $address:$port. Check the address in Dev Home and that this device is on the same network.');
      }
      if (mounted) setState(() => _step = 'Signing in to the Device Portal');
      await client.connect();
      final session = ConsoleSession(client);
      if (mounted) setState(() => _step = 'Reading installed apps');
      await session.refresh();
      final saved = await _recents.remember(SavedConsole(address, port: port, username: user));
      if (!mounted) {
        session.dispose();
        return;
      }
      setState(() => _saved = saved);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (c) => Shell(session: session, catalog: widget.catalog, onDisconnect: () => Navigator.of(c).pop()),
      ));
      session.dispose();
    } catch (e) {
      client.close();
      if (mounted) {
        setState(() => _error = e is PortalException && e.status == 401 && !_signIn
            ? 'This console asks for a username and password. Turn on portal sign-in below.'
            : friendlyError(e, address: address));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openWith(PortalClient client) async {
    setState(() => _busy = true);
    await client.connect();
    final session = ConsoleSession(client);
    await session.refresh();
    if (!mounted) {
      session.dispose();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (c) => Shell(session: session, catalog: widget.catalog, onDisconnect: () => Navigator.of(c).pop()),
    ));
    session.dispose();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Brand.s5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Image.asset('assets/logo.png', width: 44, height: 44),
                    const SizedBox(width: Brand.s3),
                    Text('PortalApp', style: text.headlineMedium),
                  ]),
                  const SizedBox(height: Brand.s3),
                  Text('Install and manage apps on your Xbox in Developer Mode.', style: text.bodyMedium?.copyWith(color: Brand.muted)),
                  const SizedBox(height: Brand.s6),
                  TextField(
                    controller: _address,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _connect(),
                    decoration: const InputDecoration(labelText: 'Console address', hintText: '192.168.1.20', helperText: 'Shown on the Dev Home screen'),
                  ),
                  const SizedBox(height: Brand.s2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Portal sign-in'),
                    subtitle: Text('Only if you set a username and password in Dev Home', style: text.bodySmall?.copyWith(fontSize: 13)),
                    value: _signIn,
                    activeThumbColor: Brand.accentInk,
                    activeTrackColor: Brand.accent,
                    onChanged: _busy ? null : (v) => setState(() => _signIn = v),
                  ),
                  if (_signIn) ...[
                    TextField(controller: _user, enabled: !_busy, decoration: const InputDecoration(labelText: 'Username')),
                    const SizedBox(height: Brand.s3),
                    TextField(
                      controller: _pass,
                      enabled: !_busy,
                      obscureText: true,
                      onSubmitted: (_) => _connect(),
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                  ],
                  const SizedBox(height: Brand.s4),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Brand.s3),
                      child: Text(_error!, style: text.bodyMedium?.copyWith(color: Brand.error)),
                    ),
                  FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? _step : 'Connect')),
                  if (_busy) const Padding(padding: EdgeInsets.only(top: Brand.s3), child: LinearProgressIndicator(minHeight: 3)),
                  if (widget.extras != null) widget.extras!(context, _busy, _openWith),
                  if (_saved.isNotEmpty) ...[
                    const SizedBox(height: Brand.s6),
                    Text('RECENT', style: text.labelMedium?.copyWith(color: Brand.muted, letterSpacing: 1)),
                    const SizedBox(height: Brand.s2),
                    for (final c in _saved)
                      ListRow(
                        title: c.port == 11443 ? c.address : '${c.address}:${c.port}',
                        subtitle: c.username == null ? null : 'Signs in as ${c.username}',
                        onTap: _busy ? null : () => _fill(c),
                        trailing: IconButton(
                          tooltip: 'Forget',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _busy
                              ? null
                              : () async {
                                  final left = await _recents.forget(c);
                                  if (mounted) setState(() => _saved = left);
                                },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
