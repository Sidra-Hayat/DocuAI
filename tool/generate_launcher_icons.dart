// Generates the legacy launcher icons under android/app/src/main/res/mipmap-*.
//
// Run with:  dart run tool/generate_launcher_icons.dart
//
// The output is committed, so this only needs re-running when the mark changes.
// It exists rather than a checked-in binary blob nobody can regenerate: the
// icon is defined here, in code, next to the colour it shares with the app
// theme.
//
// Android 8 and above use the adaptive icon in mipmap-anydpi-v26 instead, which
// is a vector and lives in the res tree directly. These PNGs are the fallback
// for API 24–25.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Matches `AppTheme.seedColor` (0xFF2563EB).
const int brandR = 0x25;
const int brandG = 0x63;
const int brandB = 0xEB;

/// Launcher icon sizes Android expects per density bucket.
const Map<String, int> densities = <String, int>{
  'mipmap-mdpi': 48,
  'mipmap-hdpi': 72,
  'mipmap-xhdpi': 96,
  'mipmap-xxhdpi': 144,
  'mipmap-xxxhdpi': 192,
};

void main() {
  final resDir = p.join('android', 'app', 'src', 'main', 'res');

  if (!Directory(resDir).existsSync()) {
    stderr.writeln('Run this from the project root: $resDir not found.');
    exitCode = 1;
    return;
  }

  densities.forEach((directory, size) {
    final file = File(p.join(resDir, directory, 'ic_launcher.png'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(img.encodePng(_icon(size)));
    stdout.writeln('wrote ${file.path} (${size}x$size)');
  });
}

/// A document sheet with a folded corner and a spark, on the brand colour.
img.Image _icon(int size) {
  final image = img.Image(width: size, height: size, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(brandR, brandG, brandB, 255));

  final unit = size / 48;
  double u(double value) => value * unit;

  final paper = img.ColorRgb8(0xFA, 0xFA, 0xFC);
  final fold = img.ColorRgb8(0xC7, 0xD6, 0xF7);
  final ink = img.ColorRgba8(brandR, brandG, brandB, 255);

  // Sheet with the top-right corner cut away.
  final left = u(10);
  final right = u(30);
  final top = u(8);
  final bottom = u(34);
  final cut = u(7);

  img.fillPolygon(
    image,
    vertices: <img.Point>[
      img.Point(left, top),
      img.Point(right - cut, top),
      img.Point(right, top + cut),
      img.Point(right, bottom),
      img.Point(left, bottom),
    ],
    color: paper,
  );

  // The fold itself, shaded so the corner reads as turned rather than clipped.
  img.fillPolygon(
    image,
    vertices: <img.Point>[
      img.Point(right - cut, top),
      img.Point(right, top + cut),
      img.Point(right - cut, top + cut),
    ],
    color: fold,
  );

  // Ruled lines standing in for text.
  final lineHeight = math.max(1.0, u(2));
  for (var i = 0; i < 3; i++) {
    final y = u(15) + i * u(5.5);
    img.fillRect(
      image,
      x1: u(14).round(),
      y1: y.round(),
      x2: (right - u(3) - (i == 2 ? u(5) : 0)).round(),
      y2: (y + lineHeight).round(),
      color: ink,
    );
  }

  // Four-point spark: the "AI" half of the name, drawn rather than lettered so
  // it survives being rendered at 48 px.
  _spark(image, cx: u(34), cy: u(34), radius: u(10), color: paper);

  return image;
}

/// A four-pointed star.
///
/// Composed from four convex triangles meeting at the centre rather than one
/// eight-vertex outline: `fillPolygon` scan-fills without handling concavity,
/// and the single-polygon version renders as a wedge.
void _spark(
  img.Image image, {
  required double cx,
  required double cy,
  required double radius,
  required img.Color color,
}) {
  final waist = radius * 0.34;

  void triangle(img.Point a, img.Point b, img.Point c) => img.fillPolygon(
    image,
    vertices: <img.Point>[a, b, c],
    color: color,
  );

  triangle(
    img.Point(cx, cy - radius),
    img.Point(cx - waist, cy),
    img.Point(cx + waist, cy),
  );
  triangle(
    img.Point(cx, cy + radius),
    img.Point(cx - waist, cy),
    img.Point(cx + waist, cy),
  );
  triangle(
    img.Point(cx - radius, cy),
    img.Point(cx, cy - waist),
    img.Point(cx, cy + waist),
  );
  triangle(
    img.Point(cx + radius, cy),
    img.Point(cx, cy - waist),
    img.Point(cx, cy + waist),
  );
}
