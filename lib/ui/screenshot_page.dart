import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../state/console_session.dart';
import '../theme/brand.dart';
import 'errors.dart';
import 'widgets.dart';

class ScreenshotPage extends StatefulWidget {
  const ScreenshotPage({super.key, required this.session});

  final ConsoleSession session;

  @override
  State<ScreenshotPage> createState() => _ScreenshotPageState();
}

class _ScreenshotPageState extends State<ScreenshotPage> {
  Uint8List? _image;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _grab();
  }

  Future<void> _grab() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await widget.session.client.screenshot();
      if (mounted) setState(() => _image = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e, address: widget.session.address));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Console screen'),
        actions: [IconButton(tooltip: 'Take another', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _grab)],
        bottom: _loading ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      body: _error != null && _image == null
          ? EmptyState(title: 'Could not get the screen', body: _error!, action: OutlinedButton(onPressed: _grab, child: const Text('Try again')))
          : _image == null
              ? const SizedBox.shrink()
              : InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Brand.line)),
                      child: Image.memory(_image!, fit: BoxFit.contain, gaplessPlayback: true),
                    ),
                  ),
                ),
    );
  }
}
