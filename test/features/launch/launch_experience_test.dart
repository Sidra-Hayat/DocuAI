import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The launcher icon and the splash, as configuration rather than as pixels.
///
/// A test cannot judge whether the mark looks right — that needs a phone, and
/// the report says so. What it can do is hold the things that break silently:
/// a density dropped by a regenerate, a themed-icon layer lost to a tool
/// upgrade, a splash attribute edited into a file the device it targets never
/// reads. Every one of those ships looking fine on the machine that made it.
///
/// These read the Android resources directly. There is no emulator and no
/// Gradle here; the files either say what they must or they do not.
void main() {
  File res(String path) => File('android/app/src/main/res/$path');

  String read(String path) {
    final file = res(path);
    expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
    return file.readAsStringSync();
  }

  /// The densities Android expects a launcher icon in.
  const densities = <String>['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

  group('the launcher icon', () {
    test('ships a legacy icon at every density', () {
      // API 24 and 25 have no adaptive icons and fall back to these. A missing
      // density is not a crash — Android scales a neighbour — which is exactly
      // why it goes unnoticed until the icon looks soft on somebody's phone.
      for (final density in densities) {
        expect(
          res('mipmap-$density/ic_launcher.png').existsSync(),
          isTrue,
          reason: 'no launcher icon for $density',
        );
      }
    });

    test('ships both adaptive layers at every density', () {
      for (final density in densities) {
        expect(
          res('drawable-$density/ic_launcher_foreground.png').existsSync(),
          isTrue,
          reason: 'no adaptive foreground for $density',
        );
        expect(
          res('drawable-$density/ic_launcher_background.png').existsSync(),
          isTrue,
          reason: 'no adaptive background for $density',
        );
      }
    });

    test('is a real adaptive icon, not a square in a mipmap', () {
      final adaptive = read('mipmap-anydpi-v26/ic_launcher.xml');

      expect(adaptive, contains('<adaptive-icon'));
      expect(adaptive, contains('@drawable/ic_launcher_background'));
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    });

    test('carries a monochrome layer for Android 13 themed icons', () {
      // Without it the launcher shows the full-colour icon on a grey plate —
      // the one icon on the home screen that has not joined in.
      expect(read('mipmap-anydpi-v26/ic_launcher.xml'), contains('monochrome'));
    });

    test('insets the foreground so the mask cannot clip it', () {
      // The artwork runs close to its canvas edge and a launcher masks away the
      // outer third. At inset 0 the viewfinder brackets are simply cut off.
      expect(read('mipmap-anydpi-v26/ic_launcher.xml'), contains('17%'));
    });
  });

  group('the splash', () {
    test('draws the mark on the brand ink before Android 12', () {
      // `drawable-v21` is the variant every device actually uses at minSdk 24;
      // the unqualified one is kept in step and is dropped at build time.
      for (final path in <String>[
        'drawable/launch_background.xml',
        'drawable-v21/launch_background.xml',
      ]) {
        final splash = read(path);

        expect(splash, contains('@color/brand_ink'), reason: path);
        expect(
          splash,
          contains('@drawable/ic_launcher_foreground'),
          reason: '$path shows no mark, only a dark rectangle',
        );
        expect(
          splash,
          contains('android:gravity="center"'),
          reason: 'a bitmap with no gravity is stretched over the whole window',
        );
      }
    });

    test('restates ink and mark in the attributes Android 12 reads', () {
      // From API 31 the platform composes the splash itself and ignores
      // `windowBackground`, so branding set only there disappears.
      for (final path in <String>[
        'values-v31/styles.xml',
        'values-night-v31/styles.xml',
      ]) {
        final styles = read(path);

        expect(
          styles,
          contains('android:windowSplashScreenBackground'),
          reason: path,
        );
        expect(
          styles,
          contains('@drawable/splash_icon'),
          reason: '$path falls back to the platform default icon',
        );
      }
    });

    test('keeps the API 31 attributes out of the files that ignore them', () {
      // They used to sit in values/styles.xml, where every device below 31 read
      // past them. Harmless, and the reason nobody noticed the pre-12 splash
      // had no icon at all.
      for (final path in <String>[
        'values/styles.xml',
        'values-night/styles.xml',
      ]) {
        expect(
          read(path),
          isNot(contains('windowSplashScreen')),
          reason: '$path sets an attribute the versions it covers cannot read',
        );
      }
    });

    test('gives the splash icon its own inset rather than reusing the launcher',
        () {
      // The platform masks a splash icon exactly as a launcher masks an
      // adaptive one. Handing it the launcher icon — already inset 17% —
      // insets the artwork twice and halves the mark.
      final icon = read('drawable/splash_icon.xml');

      expect(icon, contains('@drawable/ic_launcher_foreground'));
      expect(icon, contains('17%'));
    });

    test('is the same ink in dark mode as in light', () {
      // The splash is brand, not chrome. Following the system setting is also
      // what gives a dark-mode user a white flash on every cold start.
      for (final path in <String>[
        'values/styles.xml',
        'values-night/styles.xml',
        'values-v31/styles.xml',
        'values-night-v31/styles.xml',
      ]) {
        expect(read(path), contains('LaunchTheme'), reason: path);
      }

      expect(read('values/colors.xml'), contains('brand_ink'));
    });
  });

  group('startup', () {
    test('nothing holds the app open for effect', () {
      // The brief is explicit: no artificial delay. The composition root is the
      // only place one could hide, since it is the code that runs before the
      // first frame.
      final bootstrap = File('lib/bootstrap.dart').readAsStringSync();

      expect(
        bootstrap,
        isNot(contains('Future.delayed')),
        reason: 'a splash held open on purpose is a slower app pretending',
      );
      expect(bootstrap, isNot(contains('sleep(')));
    });

    test('the app opens on the library', () {
      // "Transitions naturally into the Home screen" is a routing fact: there
      // is no splash route to pass through, so the first frame is the library.
      final router = File(
        'lib/src/core/router/app_router.dart',
      ).readAsStringSync();

      expect(router, contains('initialLocation: AppRoutes.documents'));
    });
  });

  group('package identity', () {
    test('the application id is unchanged', () {
      // Permanent once uploaded to Play. Pinned here because it is a one-line
      // edit away from being wrong and the consequence cannot be undone.
      final gradle = File(
        'android/app/build.gradle.kts',
      ).readAsStringSync();

      expect(gradle, contains('applicationId = "com.sidrahayat.docuai"'));
      expect(gradle, contains('namespace = "com.sidrahayat.docuai"'));
    });

    test('the launcher still points at the icon and the label', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest, contains('android:label="DocuAI"'));
      expect(manifest, contains('android:theme="@style/LaunchTheme"'));
    });
  });
}
