import 'models.dart';
import 'package_info.dart';

enum InstallKind { fresh, update, reinstall, downgrade, unsigned }

class InstallPlan {
  const InstallPlan(this.kind, this.installed);

  final InstallKind kind;

  // the newest installed copy of the same app, if any
  final InstalledPackage? installed;

  // unsigned packages are refused by the console, so do not send them
  bool get allowed => kind != InstallKind.unsigned;

  String describe(PackageInfo p) => switch (kind) {
        InstallKind.fresh => 'New install, version ${p.version}',
        InstallKind.update => 'Update from ${installed!.version} to ${p.version}. Its saved data is kept.',
        InstallKind.reinstall => 'Version ${p.version} is already installed. This installs it again over the top.',
        InstallKind.downgrade => 'The console has ${installed!.version}, which is newer than ${p.version}. '
            'The console will probably refuse a downgrade.',
        InstallKind.unsigned => 'This package is not signed, and the console will not accept it.',
      };
}

InstallPlan planInstall(PackageInfo p, List<InstalledPackage> all) {
  if (!p.signed) return const InstallPlan(InstallKind.unsigned, null);
  final same = matchFamily(all, p.familyPrefix);
  if (same.isEmpty) return const InstallPlan(InstallKind.fresh, null);
  final have = same.first;
  final kind = switch (p.version.compareTo(have.version)) {
    > 0 => InstallKind.update,
    0 => InstallKind.reinstall,
    _ => InstallKind.downgrade,
  };
  return InstallPlan(kind, have);
}
