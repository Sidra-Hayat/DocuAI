import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/assistant_answer.dart';

part 'answer_citation_model.g.dart';

/// Hive representation of an [AnswerCitation].
///
/// [documentTitle] is stored rather than looked up, and that is the point: a
/// transcript records what a document was called when the answer was given.
/// Resolving the title live would rewrite history every time a document is
/// renamed.
@HiveType(typeId: HiveTypeIds.answerCitation)
class AnswerCitationModel {
  const AnswerCitationModel({
    required this.documentId,
    required this.documentTitle,
    required this.pageIndex,
    required this.snippet,
    required this.matchedTerms,
    required this.relevance,
  });

  factory AnswerCitationModel.fromEntity(AnswerCitation citation) =>
      AnswerCitationModel(
        documentId: citation.documentId,
        documentTitle: citation.documentTitle,
        pageIndex: citation.pageIndex,
        snippet: citation.snippet,
        matchedTerms: citation.matchedTerms,
        relevance: citation.relevance,
      );

  @HiveField(0)
  final String documentId;

  @HiveField(1)
  final String documentTitle;

  @HiveField(2)
  final int pageIndex;

  @HiveField(3)
  final String snippet;

  /// Nullable because transcripts written before these fields existed have no
  /// value at this index — Hive hands back null, and an older answer simply
  /// shows no matched terms rather than failing to load.
  @HiveField(4)
  final List<String>? matchedTerms;

  @HiveField(5)
  final double? relevance;

  AnswerCitation toEntity() => AnswerCitation(
    documentId: documentId,
    documentTitle: documentTitle,
    pageIndex: pageIndex,
    snippet: snippet,
    matchedTerms: matchedTerms ?? const <String>[],
    relevance: relevance ?? 0,
  );
}
