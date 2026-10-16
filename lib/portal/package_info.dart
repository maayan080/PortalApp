import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

import 'models.dart';

class PackageInfo {
  const PackageInfo({
    required this.file,
    required this.name,
    required this.displayName,
    required this.publisher,
    required this.version,
    required this.architecture,
    required this.signed,
    required this.isBundle,
    required this.bytes,
  });

  final File file;

  // the identity name, the installed family name starts with this
  final String name;
  final String displayName;
  final String publisher;
  final PackageVersion version;
  final String architecture;
  final bool signed;
  final bool isBundle;
  final int bytes;

  String get fileName => file.uri.pathSegments.last;

  // matches the installed family name, with or without a publisher hash after it
  String get familyPrefix => name;
}

class PackageFormatException implements Exception {
  PackageFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

const packageExtensions = ['appx', 'msix', 'appxbundle', 'msixbundle'];

// reads only the zip directory and one small manifest, so a 600 MB package costs nothing
Future<PackageInfo> readPackageInfo(File file) async {
  final bytes = await file.length();
  final input = InputFileStream(file.path);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (_) {
      throw PackageFormatException('${file.uri.pathSegments.last} is not an app package.');
    }

    final manifest = archive.find('AppxManifest.xml');
    final bundle = archive.find('AppxMetadata/AppxBundleManifest.xml');
    final entry = manifest ?? bundle;
    if (entry == null) {
      throw PackageFormatException('${file.uri.pathSegments.last} has no app manifest, so it is not an app package.');
    }

    final xml = XmlDocument.parse(String.fromCharCodes(entry.readBytes() ?? const []).replaceFirst('﻿', ''));
    final identity = xml.rootElement.findElements('Identity').firstOrNull;
    if (identity == null) throw PackageFormatException('The package manifest has no identity.');

    final name = identity.getAttribute('Name') ?? '';
    final version = PackageVersion.tryParse(identity.getAttribute('Version') ?? '');
    if (name.isEmpty || version == null) throw PackageFormatException('The package manifest has no usable name or version.');

    var display = xml.rootElement.findElements('Properties').firstOrNull?.findElements('DisplayName').firstOrNull?.innerText.trim() ?? '';
    // resource strings like ms-resource:AppName are resolved on the console, not here
    if (display.isEmpty || display.startsWith('ms-resource:')) display = name;

    return PackageInfo(
      file: file,
      name: name,
      displayName: display,
      publisher: identity.getAttribute('Publisher') ?? '',
      version: version,
      architecture: identity.getAttribute('ProcessorArchitecture') ?? '',
      signed: archive.find('AppxSignature.p7x') != null,
      isBundle: manifest == null,
      bytes: bytes,
    );
  } finally {
    await input.close();
  }
}
