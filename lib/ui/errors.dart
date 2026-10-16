import 'dart:async';
import 'dart:io';

import '../portal/portal_client.dart';

String friendlyError(Object e, {String? address}) {
  if (e is PortalException) return e.message;
  if (e is TimeoutException) return 'The console took too long to answer.';
  if (e is SocketException || e is HttpException || e is HandshakeException) {
    return 'Could not reach ${address ?? 'the console'}. Check the address in Dev Home and that this device is on the same network.';
  }
  return e.toString();
}
