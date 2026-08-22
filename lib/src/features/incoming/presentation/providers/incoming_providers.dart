import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/incoming_files_channel.dart';

/// The platform channel, owned for the life of the app.
///
/// A provider rather than a singleton so a widget test can override it with a
/// channel over a fake `MethodChannel` and drive the whole "Open with" flow
/// without an Android device.
final incomingFilesChannelProvider = Provider<IncomingFilesChannel>((ref) {
  final channel = IncomingFilesChannel();
  ref.onDispose(() => unawaited(channel.dispose()));
  return channel;
});
