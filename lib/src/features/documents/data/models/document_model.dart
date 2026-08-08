import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/document.dart';
import 'document_page_model.dart';

part 'document_model.g.dart';

/// Hive representation of a [Document].
///
/// Holds metadata only. Page images and generated PDFs live on disk and are
/// referenced here by relative path, because Hive is a key/value store and
/// putting megabytes of JPEG through it would load every byte into memory just
/// to render the library list.
@HiveType(typeId: HiveTypeIds.document)
class DocumentModel {
  const DocumentModel({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
    required this.tags,
    required this.pdfPath,
    required this.isFavorite,
    this.source,
  });

  factory DocumentModel.fromEntity(Document document) => DocumentModel(
    id: document.id,
    title: document.title,
    createdAt: document.createdAt,
    updatedAt: document.updatedAt,
    pages: document.pages.map(DocumentPageModel.fromEntity).toList(),
    tags: List<String>.of(document.tags),
    pdfPath: document.pdfPath,
    isFavorite: document.isFavorite,
    source: document.source.name,
  );

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3)
  final DateTime updatedAt;

  @HiveField(4)
  final List<DocumentPageModel> pages;

  @HiveField(5)
  final List<String> tags;

  /// Relative path to the exported PDF, or null if never exported.
  @HiveField(6)
  final String? pdfPath;

  @HiveField(7)
  final bool isFavorite;

  /// Appended field. Null in every record written before origins were tracked,
  /// and every one of those was scanned.
  @HiveField(8)
  final String? source;

  Document toEntity() => Document(
    id: id,
    title: title,
    createdAt: createdAt,
    updatedAt: updatedAt,
    // Sorted on read rather than trusted from disk: a record written by an
    // interrupted edit could hold pages out of order, and the whole app treats
    // `pages` as ordered.
    pages:
        (pages.map((page) => page.toEntity()).toList()
          ..sort((a, b) => a.index.compareTo(b.index))),
    tags: List<String>.unmodifiable(tags),
    pdfPath: pdfPath,
    isFavorite: isFavorite,
    source: _decodeSource(source),
  );

  /// Stored by name, like every other enum here. An index is a position in a
  /// list: inserting a case would silently reinterpret every stored value,
  /// whereas a name only breaks on a rename, which is a visible edit.
  static DocumentSource _decodeSource(String? raw) =>
      DocumentSource.values.firstWhere(
        (source) => source.name == raw,
        orElse: () => DocumentSource.scanned,
      );
}
