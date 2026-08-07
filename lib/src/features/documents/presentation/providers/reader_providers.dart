import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../../../core/storage/storage_providers.dart';

/// Font scale for the extracted-text reader.
///
/// Persisted rather than held for the session: someone who reads at a larger
/// size wants that on the next document too, not to set it again each time.
/// Written with a hand-rolled [Notifier] against the settings box, the same
/// shape as `ThemeModeController`.
class ReaderTextScaleController extends Notifier<double> {
  /// Wide enough to matter, narrow enough that the layout never breaks. The
  /// app already clamps system text scaling to 1.4x; this multiplies the
  /// reader's own body size on top of whatever the system asked for.
  static const double minScale = 0.9;
  static const double maxScale = 1.8;
  static const double step = 0.15;
  static const double defaultScale = 1;

  @override
  double build() {
    final stored = ref.watch(settingsBoxProvider).get(SettingsKeys.readerTextScale);
    return stored is num ? _clamp(stored.toDouble()) : defaultScale;
  }

  bool get canEnlarge => state < maxScale - 0.001;

  bool get canReduce => state > minScale + 0.001;

  Future<void> enlarge() => _set(state + step);

  Future<void> reduce() => _set(state - step);

  Future<void> reset() => _set(defaultScale);

  Future<void> _set(double scale) async {
    final next = _clamp(scale);
    if (next == state) return;
    state = next;
    await ref.read(settingsBoxProvider).put(SettingsKeys.readerTextScale, next);
  }

  /// Clamped on read as well as on write, so a value left by a future version
  /// with a wider range cannot render the reader unusable.
  static double _clamp(double value) => value.clamp(minScale, maxScale);
}

final readerTextScaleProvider =
    NotifierProvider<ReaderTextScaleController, double>(
      ReaderTextScaleController.new,
    );
