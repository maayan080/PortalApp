import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../portal/models.dart';
import '../theme/brand.dart';
import 'errors.dart';

void say(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> attempt(BuildContext context, Future<void> Function() action, {String? done, String? address}) async {
  try {
    await action();
    if (done != null && context.mounted) say(context, done);
    return true;
  } catch (e) {
    if (context.mounted) say(context, friendlyError(e, address: address));
    return false;
  }
}

Future<void> openLink(BuildContext context, String url) async {
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) say(context, 'Could not open $url');
}

Future<bool> confirmDelete(BuildContext context, InstalledPackage p) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete ${p.name}?'),
      content: const Text('This removes the app and everything it has saved on the console, including settings and save files. '
          'To keep its data, update the app instead.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.error, foregroundColor: const Color(0xFF2A0709)),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}

// CN=BanditVault, O=... becomes BanditVault
String shortPublisher(String publisher) => RegExp(r'CN=([^,]+)').firstMatch(publisher)?.group(1)?.trim() ?? publisher;
