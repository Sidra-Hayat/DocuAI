import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/repositories/document_repository.dart';
import '../../presentation/providers/document_providers.dart';

/// Debug-only sample data.
///
/// Scanning does not exist until Phase 3, so without this there is no way to
/// see the library screen with anything in it. Every call site is behind
/// `kDebugMode`, which is a compile-time constant — the tree shaker removes
/// this class and the sample-page renderer from release builds entirely.
///
/// Phase 8 deletes this file.
class DebugSampleSeeder {
  const DebugSampleSeeder(this._repository);

  final DocumentRepository _repository;

  static const List<({String title, int pages, List<String> tags})> _samples = [
    (title: 'Electricity bill', pages: 1, tags: <String>['bills', 'utilities']),
    (title: 'Lecture notes — week 3', pages: 3, tags: <String>['university']),
    (title: 'Rental agreement', pages: 2, tags: <String>[]),
  ];

  /// Creates a handful of documents with generated page images.
  ///
  /// Returns the number created, or the first failure encountered — seeding
  /// half a library and reporting success would be worse than stopping.
  FutureResult<int> seed() async {
    final scratch = await Directory.systemTemp.createTemp('docuai_samples');

    try {
      var created = 0;

      for (final sample in _samples) {
        final sourcePaths = <String>[];
        for (var page = 0; page < sample.pages; page++) {
          final file = File(
            p.join(scratch.path, '${sample.title}_$page.jpg'.replaceAll(' ', '_')),
          );
          await file.writeAsBytes(
            _renderPage(title: sample.title, pageNumber: page + 1),
          );
          sourcePaths.add(file.path);
        }

        final result = await _repository.createFromImages(
          title: sample.title,
          sourceImagePaths: sourcePaths,
        );

        switch (result) {
          case Failed(:final failure):
            return Failed(failure);
          case Success(:final value):
            created++;
            if (sample.tags.isNotEmpty) {
              await _repository.saveDocument(
                value.copyWith(tags: sample.tags),
              );
            }
        }
      }

      return Success(created);
    } catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'Could not create the sample documents.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      // The repository copies rather than moves, so these scratch files have
      // done their job by now.
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    }
  }

  /// Draws a page that looks enough like a scan to judge the layout: A4-ish
  /// aspect ratio, a heading, and ruled lines standing in for body text.
  List<int> _renderPage({required String title, required int pageNumber}) {
    final page = img.Image(width: 620, height: 877);
    img.fill(page, color: img.ColorRgb8(252, 251, 248));

    img.drawString(
      page,
      title,
      font: img.arial24,
      x: 40,
      y: 56,
      color: img.ColorRgb8(24, 24, 27),
    );
    img.drawString(
      page,
      'Page $pageNumber — sample data',
      font: img.arial14,
      x: 40,
      y: 92,
      color: img.ColorRgb8(120, 120, 128),
    );

    for (var line = 0; line < 22; line++) {
      final y = 150 + line * 28;
      // Vary the length so the block reads as text rather than a barcode.
      final width = 380 + (line * 53) % 160;
      img.fillRect(
        page,
        x1: 40,
        y1: y,
        x2: 40 + width,
        y2: y + 8,
        color: img.ColorRgb8(226, 226, 232),
      );
    }

    return img.encodeJpg(page, quality: 78);
  }
}

final debugSampleSeederProvider = Provider<DebugSampleSeeder>(
  (ref) => DebugSampleSeeder(ref.watch(documentRepositoryProvider)),
);
