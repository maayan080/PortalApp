import 'package:wakelock_plus/wakelock_plus.dart';

// a phone that sleeps mid upload drops the transfer, so installs hold the screen on. a failure here
// must never stop an install, and tests have no platform to ask
Future<void> keepAwake(bool on) async {
  try {
    await WakelockPlus.toggle(enable: on);
  } catch (_) {}
}
