// plain data types for the device portal, no io and no flutter

class PortalException implements Exception {
  PortalException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null ? message : '$message (http $status)';
}

class PackageVersion implements Comparable<PackageVersion> {
  const PackageVersion(this.major, this.minor, this.build, this.revision);

  final int major;
  final int minor;
  final int build;
  final int revision;

  static final _re = RegExp(r'^(\d+)\.(\d+)\.(\d+)\.(\d+)$');

  factory PackageVersion.fromJson(Map<String, dynamic> j) => PackageVersion(
        (j['Major'] as num?)?.toInt() ?? 0,
        (j['Minor'] as num?)?.toInt() ?? 0,
        (j['Build'] as num?)?.toInt() ?? 0,
        (j['Revision'] as num?)?.toInt() ?? 0,
      );

  static PackageVersion? tryParse(String s) {
    final m = _re.firstMatch(s.trim());
    if (m == null) return null;
    return PackageVersion(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!));
  }

  // numeric, never string order: 1.0.4.99 is older than 1.0.4.351
  @override
  int compareTo(PackageVersion other) {
    for (final pair in [
      [major, other.major],
      [minor, other.minor],
      [build, other.build],
      [revision, other.revision],
    ]) {
      if (pair[0] != pair[1]) return pair[0].compareTo(pair[1]);
    }
    return 0;
  }

  @override
  bool operator ==(Object other) => other is PackageVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, build, revision);

  @override
  String toString() => '$major.$minor.$build.$revision';
}

class InstalledPackage {
  const InstalledPackage({
    required this.fullName,
    required this.familyName,
    required this.relativeId,
    required this.name,
    required this.publisher,
    required this.version,
    required this.origin,
    required this.canUninstall,
    required this.uninstallDeniedReason,
    required this.listed,
    required this.users,
  });

  final String fullName;
  final String familyName;

  // the launch id, looks like Family_hash!App
  final String relativeId;
  final String name;
  final String publisher;
  final PackageVersion version;

  // PackageOrigin: 2 inbox, 3 store, 4 and 5 developer, 6 line of business
  final int origin;
  final bool canUninstall;
  final String uninstallDeniedReason;

  // installed by a developer or sideload rather than shipped with the console
  bool get isDeveloper => origin >= 4;

  // AppListEntry, 0 for packages that have no launchable app
  final bool listed;
  final List<String> users;

  factory InstalledPackage.fromJson(Map<String, dynamic> j) => InstalledPackage(
        fullName: j['PackageFullName'] as String? ?? '',
        familyName: j['PackageFamilyName'] as String? ?? '',
        relativeId: j['PackageRelativeId'] as String? ?? '',
        name: _bestName(j),
        publisher: j['Publisher'] as String? ?? '',
        version: PackageVersion.fromJson((j['Version'] as Map?)?.cast<String, dynamic>() ?? const {}),
        origin: (j['PackageOrigin'] as num?)?.toInt() ?? 0,
        canUninstall: j['CanUninstall'] as bool? ?? false,
        uninstallDeniedReason: j['UninstallDeniedReason'] as String? ?? '',
        listed: ((j['AppListEntry'] as num?)?.toInt() ?? 0) != 0,
        users: [
          for (final u in (j['RegisteredUsers'] as List? ?? const []))
            if (u is Map) (u['UserDisplayName'] as String? ?? '') else u.toString(),
        ],
      );

  // some system apps are named just ".", so fall back to the display name
  static String _bestName(Map<String, dynamic> j) {
    final real = RegExp(r'[A-Za-z0-9]');
    for (final k in ['Name', 'PackageDisplayName']) {
      final v = (j[k] as String? ?? '').trim();
      if (real.hasMatch(v)) return v;
    }
    return j['PackageFamilyName'] as String? ?? '';
  }

  @override
  String toString() => fullName;
}

// the portal's install progress, Code 0 is done and 3 is still working
class InstallState {
  const InstallState({required this.code, required this.success, required this.codeText, required this.reason});

  final int code;
  final bool success;
  final String codeText;
  final String reason;

  bool get done => code == 0;
  bool get working => code == 3;

  factory InstallState.fromJson(Map<String, dynamic> j) => InstallState(
        code: (j['Code'] as num?)?.toInt() ?? 0,
        success: j['Success'] as bool? ?? true,
        codeText: j['CodeText'] as String? ?? '',
        reason: j['Reason'] as String? ?? '',
      );
}

class FileEntry {
  const FileEntry({required this.name, required this.isDir, required this.size, required this.path, this.created});

  final String name;
  final bool isDir;
  final int? size;
  final DateTime? created;

  // the folder this entry sits in, like \LocalState
  final String path;

  factory FileEntry.fromJson(Map<String, dynamic> j, String path) => FileEntry(
        name: j['Name'] as String? ?? '',
        // Type is a file attribute bitmask, 0x10 is a folder. a folder can carry more
        // bits, 8208 for AC
        isDir: ((j['Type'] as num?)?.toInt() ?? 0) & 0x10 != 0,
        // the portal has used both names across console builds
        size: ((j['FileSize'] ?? j['SizeInBytes']) as num?)?.toInt(),
        path: path,
        created: _fromFileTime((j['DateCreated'] as num?)?.toInt()),
      );

  // windows file time counts 100 ns ticks from 1601
  static DateTime? _fromFileTime(int? t) {
    if (t == null || t <= 0) return null;
    return DateTime.fromMicrosecondsSinceEpoch((t - 116444736000000000) ~/ 10, isUtc: true).toLocal();
  }
}

// installed packages of one app, newest first. name is the package identity, like
// BanditVault.ADFYT. the console reports the family name as the bare identity, other
// builds add a publisher hash after an underscore, so both count, and a longer name
// that merely starts the same does not
List<InstalledPackage> matchFamily(Iterable<InstalledPackage> all, String name) {
  final id = name.endsWith('_') ? name.substring(0, name.length - 1) : name;
  final hits = all.where((p) => p.familyName == id || p.familyName.startsWith('${id}_')).toList();
  hits.sort((a, b) => b.version.compareTo(a.version));
  return hits;
}
