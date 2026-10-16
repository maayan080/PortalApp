import 'package:flutter/material.dart';

import '../portal/portal_client.dart';
import '../state/console_session.dart';
import 'errors.dart';
import 'file_host.dart';
import 'keep_awake.dart';

class FilesPage extends StatefulWidget {
  FilesPage({super.key, required this.session, required this.package, FileHost? host}) : host = host ?? DeviceFileHost();

  final ConsoleSession session;
  final InstalledPackage package;
  final FileHost host;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  static const _root = r'\';

  String _path = _root;
  List<FileEntry> _items = [];
  bool _loading = true;
  String? _error;

  // a transfer in flight, progress is null while the size is unknown
  String? _busy;
  double? _progress;

  PortalClient get _client => widget.session.client;
  InstalledPackage get _pkg => widget.package;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? path]) async {
    final target = path ?? _path;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _client.listFiles(_pkg, path: target);
      items.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _path = target;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e, address: widget.session.address);
        _loading = false;
      });
    }
  }

  String _child(String name) => _path == _root ? '\\$name' : '$_path\\$name';

  String get _parent {
    final i = _path.lastIndexOf(r'\');
    return i <= 0 ? _root : _path.substring(0, i);
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String _size(int? b) {
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _download(FileEntry e) async {
    try {
      final target = await widget.host.downloadTarget(e.name);
      if (target == null) return;
      keepAwake(true);
      setState(() {
        _busy = 'Downloading ${e.name}';
        _progress = null;
      });
      final saved = await _client.download(_pkg, e.name, target, path: _path, onProgress: (got, total) {
        if (mounted) setState(() => _progress = total > 0 ? got / total : null);
      });
      _say(await widget.host.finished(saved));
    } catch (err) {
      _say(friendlyError(err, address: widget.session.address));
    } finally {
      keepAwake(false);
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _upload() async {
    try {
      final files = await widget.host.pickUploads();
      if (files.isEmpty) return;
      keepAwake(true);
      var failed = 0;
      for (var i = 0; i < files.length; i++) {
        final name = files[i].uri.pathSegments.last;
        setState(() {
          _busy = files.length == 1 ? 'Uploading $name' : 'Uploading $name (${i + 1} of ${files.length})';
          _progress = 0;
        });
        try {
          await _client.upload(_pkg, files[i], path: _path, onProgress: (sent, total) {
            if (mounted) setState(() => _progress = total > 0 ? sent / total : null);
          });
        } catch (err) {
          failed++;
          _say(friendlyError(err, address: widget.session.address));
        }
      }
      await _load();
      if (failed == 0) _say(files.length == 1 ? 'Uploaded ${files.first.uri.pathSegments.last}' : 'Uploaded ${files.length} files');
    } catch (err) {
      _say(friendlyError(err, address: widget.session.address));
    } finally {
      keepAwake(false);
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _newFolder() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _FolderNameDialog());
    if (name == null || name.isEmpty) return;
    if (name.contains(RegExp(r'[\\/:*?"<>|]'))) {
      _say('A folder name cannot contain \\ / : * ? " < > |');
      return;
    }
    try {
      await _client.makeFolder(_pkg, _path, name);
      await _load();
      // the portal answers the same way for every failure, so check it is really there
      if (!_items.any((e) => e.isDir && e.name == name)) _say('The console would not create "$name" here.');
    } catch (err) {
      _say(friendlyError(err, address: widget.session.address));
    }
  }

  Future<void> _delete(FileEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: const Text('This removes the file from the console. It cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _client.deleteFile(_pkg, e.name, path: _path);
      await _load();
      _say('${e.name} deleted');
    } catch (err) {
      _say(friendlyError(err, address: widget.session.address));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atRoot = _path == _root;
    final working = _busy != null;
    return PopScope(
      // back climbs out of folders before it leaves the page, and does nothing mid transfer
      canPop: atRoot && !working,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !working) _load(_parent);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_pkg.name, style: theme.textTheme.titleMedium),
              Text(atRoot ? 'App data' : _path, style: theme.textTheme.bodySmall),
            ],
          ),
          actions: [
            IconButton(tooltip: 'Upload files', icon: const Icon(Icons.upload_file), onPressed: working || _loading ? null : _upload),
            IconButton(tooltip: 'New folder', icon: const Icon(Icons.create_new_folder_outlined), onPressed: working || _loading || atRoot ? null : _newFolder),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: working || _loading ? null : _load),
          ],
          bottom: _loading || working
              ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: working ? _progress : null))
              : null,
        ),
        body: Column(
          children: [
            if (working)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Align(alignment: Alignment.centerLeft, child: Text(_busy!, style: theme.textTheme.bodySmall)),
              ),
            Expanded(child: _body(theme, atRoot)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, bool atRoot) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty && !_loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            atRoot
                ? 'This app has not created any data yet. Run it once on the console, then refresh.'
                : 'This folder is empty.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final e = _items[i];
        return ListTile(
          leading: Icon(e.isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
          title: Text(e.name),
          subtitle: e.isDir ? null : Text(_size(e.size)),
          onTap: _busy != null ? null : (e.isDir ? () => _load(_child(e.name)) : () => _download(e)),
          trailing: e.isDir
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Download', icon: const Icon(Icons.download), onPressed: _busy != null ? null : () => _download(e)),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _busy != null ? null : () => _delete(e)),
                ]),
        );
      },
    );
  }
}

// owns its controller so it is disposed with the dialog, not while the dialog is still
// animating out
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog();

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New folder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Folder name'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Create')),
      ],
    );
  }
}
