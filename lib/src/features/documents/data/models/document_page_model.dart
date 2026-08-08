import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/document_page.dart';

part 'document_page_model.g.dart';

/// Hive representation of a [DocumentPage].
///
/// Separate from the entity so the persisted schema can change without
/// reshaping business logic — and so the domain layer never imports Hive.
///
/// [ocrStatus] is stored as the enum's **name**, not its index. An index is a
/// position in a list: inserting a case into [OcrStatus] would silently
/// reinterpret every stored value. A name only breaks if the case is renamed,
/// which is a visible edit, and [_decodeStatus] falls back rather than throwing
/// when it meets a value it does not recognise.
@HiveType(typeId: HiveTypeIds.documentPage)
class DocumentPageModel {
  const DocumentPageModel({
    required this.id,
    required this.imagePath,
    required this.index,
    required this.text,
    required this.ocrStatus,
    this.kind,
    this.textEditedAt,
  });

  factory DocumentPageModel.fromEntity(DocumentPage page) => DocumentPageModel(
    id: page.id,
    imagePath: page.imagePath,
    index: page.index,
    text: page.text,
    ocrStatus: page.ocrStatus.name,
    kind: page.kind.name,
    textEditedAt: page.textEditedAt,
  );

  @HiveField(0)
  final String id;

  /// Relative to the app documents directory. Never absolute — see
  /// `StoragePaths`.
  ///
  /// Null for a page with no image. Widened from a non-null `String`, which is
  /// safe in this direction only: every record written before text pages
  /// existed holds a string here and still reads.
  @HiveField(1)
  final String? imagePath;

  @HiveField(2)
  final int index;

  @HiveField(3)
  final String text;

  @HiveField(4)
  final String ocrStatus;

  /// Appended field. Null in every record written before page kinds existed,
  /// which is exactly the set of records that are scans — hence the fallback.
  @HiveField(5)
  final String? kind;

  /// Appended field. Null in every record written before corrections were
  /// tracked — and null is exactly right for those, since none had been
  /// corrected.
  @HiveField(6)
  final DateTime? textEditedAt;

  DocumentPage toEntity() => DocumentPage(
    id: id,
    imagePath: imagePath,
    index: index,
    text: text,
    ocrStatus: _decodeStatus(ocrStatus),
    kind: _decodeKind(kind),
    textEditedAt: textEditedAt,
  );

  /// Defensive: an unknown status means the record was written by a different
  /// version, and treating it as pending schedules a harmless re-run rather
  /// than crashing the library screen on open.
  static OcrStatus _decodeStatus(String raw) => OcrStatus.values.firstWhere(
    (status) => status.name == raw,
    orElse: () => OcrStatus.pending,
  );

  /// Absent means a record from before this field existed, and every one of
  /// those is a scan. An unrecognised value means a record from a *later*
  /// version; falling back keeps the library openable after a downgrade
  /// instead of throwing on the page that introduced the new kind.
  static PageKind _decodeKind(String? raw) => PageKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => PageKind.scanned,
  );
}
