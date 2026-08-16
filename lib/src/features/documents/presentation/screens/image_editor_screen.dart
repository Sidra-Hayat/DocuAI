import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../data/datasources/inline_image_transformer.dart';

/// What the editor was closed with.
sealed class ImageEditorResult {
  const ImageEditorResult();
}

/// Apply this rotation and crop to the picture.
final class ImageEditApplied extends ImageEditorResult {
  const ImageEditApplied(this.edit);

  final InlineImageEdit edit;
}

/// Take the picture out of the document.
final class ImageEditDeleted extends ImageEditorResult {
  const ImageEditDeleted();
}

/// Straightening and trimming a picture in a document.
///
/// Deliberately two operations and no more. A document editor needs a page the
/// right way up with the desk cropped off it; filters, drawing and adjustment
/// panels belong to a photo app and would be four more things to keep working
/// in a release build.
///
/// Returns an [ImageEditorResult], or null if the user backed out.
class ImageEditorScreen extends StatefulWidget {
  const ImageEditorScreen({required this.imagePath, super.key});

  /// Absolute path to the picture inside the document's own storage.
  final String imagePath;

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  /// The picture's own pixel size, needed to letterbox the preview correctly.
  Size? _intrinsic;
  Object? _loadFailure;

  int _quarterTurns = 0;

  /// The kept region, in fractions of the rotated picture.
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);

  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolveIntrinsicSize();
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  /// Reads the picture's dimensions.
  ///
  /// Needed because the preview is letterboxed inside whatever space the phone
  /// has: without the aspect ratio there is no way to know which part of that
  /// box is picture, and a crop drawn over the box would map onto the wrong
  /// pixels.
  void _resolveIntrinsicSize() {
    final provider = FileImage(File(widget.imagePath));

    _listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        final image = info.image;
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(
          () => _intrinsic = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          ),
        );
      },
      onError: (Object error, StackTrace? _) {
        if (mounted) setState(() => _loadFailure = error);
      },
    );

    _stream = provider.resolve(ImageConfiguration.empty)
      ..addListener(_listener!);
  }

  /// The picture's aspect after the turns applied so far.
  double get _rotatedAspect {
    final size = _intrinsic!;
    final quarter = _quarterTurns % 4;
    return quarter.isOdd
        ? size.height / size.width
        : size.width / size.height;
  }

  void _rotate() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      // The crop is expressed against what the user is looking at, and they are
      // now looking at something with a different shape. Keeping the old
      // fractions would leave a box that no longer frames what it framed.
      _crop = const Rect.fromLTWH(0, 0, 1, 1);
    });
  }

  void _reset() => setState(() {
    _quarterTurns = 0;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
  });

  bool get _isCropped =>
      _crop.left > 0.001 ||
      _crop.top > 0.001 ||
      _crop.right < 0.999 ||
      _crop.bottom < 0.999;

  bool get _hasChanges => _quarterTurns % 4 != 0 || _isCropped;

  void _apply() => Navigator.of(context).pop(
    ImageEditApplied(
      InlineImageEdit(
        quarterTurns: _quarterTurns,
        crop: _isCropped ? _crop : null,
      ),
    ),
  );

  Future<void> _confirmDelete() async {
    final removed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this picture?'),
        content: const Text(
          'It is taken out of the document. The rest of the page is not '
          'affected.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (removed != true || !mounted) return;
    Navigator.of(context).pop(const ImageEditDeleted());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // Dark surround, like the page viewer: judging whether a page is straight
      // is easier without a bright field competing with it. The controls stay
      // on the app's own colours so it still reads as DocuAI.
      backgroundColor: const Color(0xFF0B0E11),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Edit picture'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Remove this picture',
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          AppSpacing.gapHorizontalXs,
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildPreview()),
          _Controls(
            onRotate: _intrinsic == null ? null : _rotate,
            onReset: _hasChanges ? _reset : null,
            onCancel: () => Navigator.of(context).pop(),
            onApply: _intrinsic == null ? null : _apply,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_loadFailure != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Text(
            'This picture could not be opened. It may have been removed from '
            'this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ),
      );
    }

    if (_intrinsic == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Where the picture actually lands inside the space available, once
          // it has been fitted and letterboxed. The crop overlay is laid out
          // against this rather than against the whole box.
          final available = Size(constraints.maxWidth, constraints.maxHeight);
          final fitted = _fit(_rotatedAspect, available);

          return Center(
            child: SizedBox(
              width: fitted.width,
              height: fitted.height,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RotatedBox(
                    quarterTurns: _quarterTurns,
                    child: Image.file(
                      File(widget.imagePath),
                      fit: BoxFit.fill,
                      // The preview is re-read after every rotation; without a
                      // key the cached decode is reused and the picture appears
                      // not to turn.
                      key: ValueKey<int>(_quarterTurns),
                    ),
                  ),
                  CropOverlay(
                    crop: _crop,
                    onChanged: (value) => setState(() => _crop = value),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// `BoxFit.contain` arithmetic, done here because the overlay needs the
  /// result rather than just the painted output.
  static Size _fit(double aspect, Size available) {
    final byWidth = Size(available.width, available.width / aspect);
    return byWidth.height <= available.height
        ? byWidth
        : Size(available.height * aspect, available.height);
  }
}

/// The crop rectangle: drag inside to move it, drag a corner to resize it.
///
/// Rectangular only, which is what a document picture needs. Rotation of the
/// crop box itself, aspect-ratio locks and perspective correction are the
/// scanner's job, and it already does them.
class CropOverlay extends StatelessWidget {
  const CropOverlay({required this.crop, required this.onChanged, super.key});

  /// Fractions of the picture, `0..1`.
  final Rect crop;
  final ValueChanged<Rect> onChanged;

  /// How small the kept region may get, as a fraction.
  ///
  /// A crop that can be dragged to nothing produces an image the encoder
  /// refuses, and a box smaller than a fingertip cannot be dragged back.
  static const double minimum = 0.08;

  /// Touch target for a corner. Larger than the handle it draws, because a
  /// corner is grabbed with a thumb rather than a mouse.
  static const double handleTouchSize = 48;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final rect = Rect.fromLTRB(
          crop.left * size.width,
          crop.top * size.height,
          crop.right * size.width,
          crop.bottom * size.height,
        );

        void move(Offset delta) {
          final dx = delta.dx / size.width;
          final dy = delta.dy / size.height;

          // Clamped as a whole so dragging against an edge slides along it
          // rather than stopping the gesture dead.
          final left = (crop.left + dx).clamp(0.0, 1 - crop.width);
          final top = (crop.top + dy).clamp(0.0, 1 - crop.height);

          onChanged(
            Rect.fromLTWH(left, top, crop.width, crop.height),
          );
        }

        void resize(Offset delta, {required bool left, required bool top}) {
          final dx = delta.dx / size.width;
          final dy = delta.dy / size.height;

          var next = Rect.fromLTRB(
            left ? crop.left + dx : crop.left,
            top ? crop.top + dy : crop.top,
            left ? crop.right : crop.right + dx,
            top ? crop.bottom : crop.bottom + dy,
          );

          next = Rect.fromLTRB(
            next.left.clamp(0.0, next.right - minimum),
            next.top.clamp(0.0, next.bottom - minimum),
            next.right.clamp(next.left + minimum, 1.0),
            next.bottom.clamp(next.top + minimum, 1.0),
          );

          onChanged(next);
        }

        return Stack(
          children: <Widget>[
            // Everything outside the crop, dimmed. It is what makes the box
            // read as "this is what you keep" rather than as a frame drawn on
            // top of the picture.
            IgnorePointer(
              child: CustomPaint(
                size: size,
                painter: _ScrimPainter(rect),
              ),
            ),
            Positioned.fromRect(
              rect: rect,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanUpdate: (details) => move(details.delta),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            for (final corner in _Corner.values)
              Positioned(
                left: (corner.isLeft ? rect.left : rect.right) -
                    handleTouchSize / 2,
                top: (corner.isTop ? rect.top : rect.bottom) -
                    handleTouchSize / 2,
                width: handleTouchSize,
                height: handleTouchSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) => resize(
                    details.delta,
                    left: corner.isLeft,
                    top: corner.isTop,
                  ),
                  child: Center(
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        border: Border.all(
                          color: Colors.black26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _Corner {
  topLeft(isLeft: true, isTop: true),
  topRight(isLeft: false, isTop: true),
  bottomLeft(isLeft: true, isTop: false),
  bottomRight(isLeft: false, isTop: false);

  const _Corner({required this.isLeft, required this.isTop});

  final bool isLeft;
  final bool isTop;
}

class _ScrimPainter extends CustomPainter {
  const _ScrimPainter(this.window);

  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: .55);

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(window),
      ),
      scrim,
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter oldDelegate) =>
      oldDelegate.window != window;
}

/// Rotate, reset, cancel and apply.
///
/// Apply is the one filled button on the screen: there is exactly one primary
/// action here and it should be obvious which.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.onRotate,
    required this.onReset,
    required this.onCancel,
    required this.onApply,
    required this.theme,
  });

  final VoidCallback? onRotate;
  final VoidCallback? onReset;
  final VoidCallback onCancel;
  final VoidCallback? onApply;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _ToolButton(
                  icon: Icons.rotate_90_degrees_cw_outlined,
                  label: 'Rotate',
                  onPressed: onRotate,
                ),
                AppSpacing.gapHorizontalLg,
                _ToolButton(
                  icon: Icons.restart_alt,
                  label: 'Reset',
                  onPressed: onReset,
                ),
              ],
            ),
            AppSpacing.gapMd,
            Text(
              'Drag the corners to trim the edges.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
            AppSpacing.gapMd,
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                AppSpacing.gapHorizontalMd,
                Expanded(
                  child: FilledButton(
                    onPressed: onApply,
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colour = enabled ? Colors.white : Colors.white30;

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: colour),
              AppSpacing.gapXs,
              Text(label, style: TextStyle(color: colour, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
