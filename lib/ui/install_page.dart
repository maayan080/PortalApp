import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../portal/install_plan.dart';
import '../portal/package_info.dart';
import '../state/console_session.dart';
import 'errors.dart';
import 'keep_awake.dart';

enum _Stage { pick, ready, working, done }

// lets the file picker be swapped out in tests
typedef PickFiles = Future<List<File>> Function({required bool multiple});

Future<List<File>> pickPackageFiles({required bool multiple}) async {
  final List<PlatformFile> picked;
  if (multiple) {
    picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: packageExtensions);
  } else {
    final one = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: packageExtensions);
    picked = one == null ? [] : [one];
  }
  return [for (final f in picked) if (f.path != null) File(f.path!)];
}

class InstallPage extends StatefulWidget {
  const InstallPage({super.key, required this.session, this.pick = pickPackageFiles});

  final ConsoleSession session;
  final PickFiles pick;

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  _Stage _stage = _Stage.pick;
  PackageInfo? _info;
  InstallPlan? _plan;
  final List<File> _deps = [];
  String? _error;
  String? _result;

  // upload progress, null while the console is registering the package
  double? _progress;
  int _sent = 0;

  ConsoleSession get s => widget.session;

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  Future<void> _choose() async {
    setState(() => _error = null);
    try {
      final files = await widget.pick(multiple: false);
      if (files.isEmpty) return;
      final info = await readPackageInfo(files.first);
      // the list may have changed since the apps page loaded, and this is what the plan compares to
      await s.refresh();
      setState(() {
        _info = info;
        _plan = planInstall(info, s.packages);
        _stage = _Stage.ready;
      });
    } catch (e) {
      setState(() => _error = friendlyError(e, address: s.address));
    }
  }

  Future<void> _addDeps() async {
    final files = await widget.pick(multiple: true);
    setState(() {
      for (final f in files) {
        if (!_deps.any((d) => d.path == f.path) && f.path != _info?.file.path) _deps.add(f);
      }
    });
  }

  Future<void> _install() async {
    final info = _info!;
    keepAwake(true);
    setState(() {
      _stage = _Stage.working;
      _error = null;
      _progress = 0;
      _sent = 0;
    });
    try {
      final p = await s.install(
        info,
        dependencies: _deps,
        onUpload: (done, total) {
          if (!mounted) return;
          setState(() {
            _sent = done;
            _progress = done >= total ? null : done / total;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _result = '${p.name} ${p.version} is installed.';
        _stage = _Stage.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e, address: s.address);
        _stage = _Stage.ready;
      });
    } finally {
      keepAwake(false);
    }
  }

  @override
  void dispose() {
    keepAwake(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // leaving mid-upload would leave the console with half a package
      canPop: _stage != _Stage.working,
      child: Scaffold(
        appBar: AppBar(title: const Text('Install an app')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_stage == _Stage.pick) ...[
                    Text('Choose a signed package (.appx, .msix or a bundle). '
                        'If the app is already installed it is updated in place and keeps its data.'),
                    const SizedBox(height: 20),
                    FilledButton.icon(onPressed: _choose, icon: const Icon(Icons.folder_open), label: const Text('Choose package')),
                  ],
                  if (_stage != _Stage.pick && _info != null) _summary(theme),
                  if (_stage == _Stage.ready) ..._readyActions(theme),
                  if (_stage == _Stage.working) ..._workingView(theme),
                  if (_stage == _Stage.done) ...[
                    const SizedBox(height: 24),
                    Text(_result!, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(ThemeData theme) {
    final info = _info!;
    final plan = _plan!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(info.displayName, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${info.fileName}  ${_mb(info.bytes)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(plan.describe(info),
                style: TextStyle(color: plan.kind == InstallKind.unsigned || plan.kind == InstallKind.downgrade ? theme.colorScheme.error : null)),
          ],
        ),
      ),
    );
  }

  List<Widget> _readyActions(ThemeData theme) {
    return [
      const SizedBox(height: 16),
      for (final d in _deps)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.extension, size: 18),
          title: Text(d.uri.pathSegments.last),
          trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _deps.remove(d))),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: _addDeps, icon: const Icon(Icons.add), label: const Text('Add dependency packages')),
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _plan!.allowed ? _install : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(switch (_plan!.kind) {
            InstallKind.update => 'Update',
            InstallKind.reinstall => 'Reinstall',
            _ => 'Install',
          }),
        ),
      ),
      TextButton(onPressed: _choose, child: const Text('Choose a different package')),
    ];
  }

  List<Widget> _workingView(ThemeData theme) {
    final total = _info!.bytes;
    return [
      const SizedBox(height: 24),
      LinearProgressIndicator(value: _progress),
      const SizedBox(height: 8),
      Text(_progress == null ? 'The console is installing it...' : 'Sending ${_mb(_sent)} of ${_mb(total)}'),
      const SizedBox(height: 4),
      Text('Keep this screen open until it finishes.', style: theme.textTheme.bodySmall),
    ];
  }
}
