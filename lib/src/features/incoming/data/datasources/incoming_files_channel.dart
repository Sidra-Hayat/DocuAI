import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/incoming_file.dart';

/// The Dart end of "Open with DocuAI".
///
/// One channel, used in both directions, and the direction is the whole story:
///
///  * [takePending] is Dart asking what arrived *before it was listening*. That
///    is the cold-start case — Android created the activity with the intent
///    attached and the copy finished while the Dart isolate was still starting.
///    Calling it also tells the platform side that pushes may now be sent.
///  * [deliveries] carries everything after that. A file shared while the app
///    is on screen, or while it is in the background, reaches `onNewIntent` and
///    comes straight down this stream.
///
/// Both paths end in the same [IncomingDelivery], so nothing above here has to
/// know which of the three states the app was in.
class IncomingFilesChannel {
  IncomingFilesChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const String channelName = 'com.sidrahayat.docuai/incoming';
  static const String takePendingMethod = 'takePending';
  static const String onFilesMethod = 'onIncomingFiles';

  final MethodChannel _channel;

  final StreamController<IncomingDelivery> _deliveries =
      StreamController<IncomingDelivery>.broadcast();

  /// Files handed over while the app was already running.
  Stream<IncomingDelivery> get deliveries => _deliveries.stream;

  /// Whatever arrived before this side was listening. Empty on an ordinary
  /// launch from the home screen, which is the common case by far.
  Future<List<IncomingDelivery>> takePending() async {
    try {
      final pending = await _channel.invokeListMethod<Object?>(
        takePendingMethod,
      );

      return (pending ?? const <Object?>[])
          .map(_parseDelivery)
          .whereType<IncomingDelivery>()
          .toList();
    } on MissingPluginException {
      // No host activity: a widget test, or a platform without the channel.
      // Nothing was shared, which is the truthful answer in both.
      return const <IncomingDelivery>[];
    } on PlatformException {
      return const <IncomingDelivery>[];
    }
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _deliveries.close();
  }

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != onFilesMethod) return null;

    final delivery = _parseDelivery(call.arguments);
    if (delivery != null && !_deliveries.isClosed) {
      _deliveries.add(delivery);
    }
    return null;
  }

  /// Turns one platform map into a delivery, or null if it is unusable.
  ///
  /// Written defensively even though the far side is ours. A method channel
  /// hands over `Map<Object?, Object?>` whatever was sent, and a cast that
  /// assumes otherwise is the classic way this kind of bridge starts throwing
  /// on one Android version and not another.
  static IncomingDelivery? _parseDelivery(Object? raw) {
    if (raw is! Map) return null;

    final rawFiles = raw['files'];
    if (rawFiles is! List) return null;

    final files = <IncomingFile>[];
    for (final entry in rawFiles) {
      if (entry is! Map) continue;

      final path = entry['path'];
      final name = entry['name'];
      if (path is! String || path.isEmpty) continue;

      final size = entry['sizeBytes'];
      final mimeType = entry['mimeType'];

      files.add(
        IncomingFile(
          path: path,
          name: name is String && name.isNotEmpty ? name : 'Shared file',
          sizeBytes: size is int ? size : 0,
          mimeType: mimeType is String && mimeType.isNotEmpty ? mimeType : null,
        ),
      );
    }

    final rejected = raw['rejected'];

    return IncomingDelivery(
      files: files,
      rejected: rejected is int && rejected > 0 ? rejected : 0,
    );
  }
}
