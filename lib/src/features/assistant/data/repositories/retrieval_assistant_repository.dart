import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../datasources/chat_history_local_data_source.dart';
import '../datasources/passage_extractor.dart';
import '../datasources/passage_ranker.dart';
import '../datasources/question_analyzer.dart';
import '../models/chat_message_model.dart';

/// The offline assistant: retrieval and extractive answering, with no model.
///
/// Answers are **quoted, never composed**. The reply is the highest-scoring
/// passage from the user's own documents, whitespace-normalised and nothing
/// else. That is what makes an assistant defensible with no language model
/// behind it: there is no step at which anything could be invented, because
/// every character shown was read off a page the user scanned.
///
/// `AnswerSource.onDeviceModel` exists on the entity for the optional
/// enhancement. Nothing here sets it — a generative path would replace
/// [_compose] alone, since retrieval already produces exactly the grounded
/// context such a model would need.
class RetrievalAssistantRepository implements AssistantRepository {
  const RetrievalAssistantRepository({
    required SearchRepository search,
    required DocumentRepository documents,
    required ChatHistoryLocalDataSource history,
  }) : _search = search,
       _documents = documents,
       _history = history;

  final SearchRepository _search;
  final DocumentRepository _documents;
  final ChatHistoryLocalDataSource _history;

  /// Documents taken from the first stage. Wide enough that the answer is
  /// rarely outside it, narrow enough that passage extraction stays cheap.
  static const int maxDocuments = 6;

  /// Passages kept after ranking.
  static const int maxPassages = 4;

  /// At most this many passages from any one document, so a long document
  /// cannot crowd out a better answer elsewhere in the library.
  static const int maxPassagesPerDocument = 2;

  /// Total characters of context retained.
  ///
  /// Extractive answering barely needs a budget — but it is the same knob a
  /// prompt window needs, so the optional model can be added without the
  /// retrieval layer changing shape.
  static const int contextCharacterBudget = 1200;

  static const String notFoundMessage =
      'I could not find an answer to that in your documents.';

  static const String noTextMessage =
      'None of your documents have had their text recognised yet, so there is '
      'nothing for me to read. Open a document to recognise its text.';

  static const String emptyLibraryMessage =
      'There are no documents to search yet. Scan one and I can answer '
      'questions about it.';

  static const String unclearMessage =
      'I need something more specific to look for. Try naming a word that '
      'appears on the page — an amount, a date, or a company name.';

  @override
  FutureResult<AssistantAnswer> ask(
    String question, {
    String? documentId,
  }) async {
    try {
      final analyzed = QuestionAnalyzer.analyze(question);
      if (analyzed.isEmpty) {
        return const Success(
          AssistantAnswer(
            text: unclearMessage,
            kind: AnswerKind.unclearQuestion,
          ),
        );
      }

      final candidates = await _candidates(analyzed, documentId);
      switch (candidates) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(:final value):
          return Success(await _answerFrom(analyzed, value));
      }
    } catch (error, stackTrace) {
      return Failed(
        AssistantFailure(
          'The assistant could not answer that.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Stage one: narrow the library to the documents worth reading.
  FutureResult<({List<Document> documents, Map<String, double> priors})>
  _candidates(AnalyzedQuestion question, String? documentId) async {
    // "Ask this document" skips retrieval entirely — the user has already said
    // where to look, and second-guessing that with a corpus-wide search would
    // answer a question they did not ask.
    if (documentId != null) {
      final loaded = await _documents.getDocument(documentId);
      return switch (loaded) {
        Failed(:final failure) => Failed(failure),
        Success(:final value) => Success((
          documents: <Document>[value],
          priors: <String, double>{value.id: 1},
        )),
      };
    }

    final found = await _search.search(question.terms.join(' '));
    return switch (found) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success((
        documents: value
            .take(maxDocuments)
            .map((hit) => hit.document)
            .toList(growable: false),
        priors: PassageRanker.priorsFrom(<String, double>{
          for (final hit in value.take(maxDocuments)) hit.document.id: hit.score,
        }),
      )),
    };
  }

  /// Stage two: find the answer inside those documents.
  Future<AssistantAnswer> _answerFrom(
    AnalyzedQuestion question,
    ({List<Document> documents, Map<String, double> priors}) candidates,
  ) async {
    if (candidates.documents.isEmpty) {
      // Nothing matched — but "no documents match" and "no documents exist"
      // send the user to completely different places, so it is worth one more
      // read to tell them apart.
      return _emptyHanded();
    }

    // Distinguishes "nothing matched" from "there is nothing to match
    // against" — the second is the user's to fix, and saying so is the
    // difference between an actionable answer and a dead end.
    if (!candidates.documents.any((document) => document.hasText)) {
      return AssistantAnswer(
        text: noTextMessage,
        kind: AnswerKind.noRecognisedText,
        documentsSearched: candidates.documents.length,
      );
    }

    final passages = <Passage>[
      for (final document in candidates.documents)
        ...PassageExtractor.extract(document),
    ];

    final ranked = PassageRanker.rank(
      question: question,
      passages: passages,
      documentPriors: candidates.priors,
    );

    final selected = _select(ranked);
    if (selected.isEmpty) {
      return AssistantAnswer(
        text: notFoundMessage,
        kind: AnswerKind.noMatch,
        documentsSearched: candidates.documents.length,
      );
    }

    return _compose(selected, candidates.documents.length);
  }

  /// Which flavour of "nothing" this was.
  Future<AssistantAnswer> _emptyHanded() async {
    final library = await _documents.getDocuments();

    if (library case Success(:final value)) {
      if (value.isEmpty) {
        return const AssistantAnswer(
          text: emptyLibraryMessage,
          kind: AnswerKind.emptyLibrary,
        );
      }
      if (!value.any((document) => document.hasText)) {
        return AssistantAnswer(
          text: noTextMessage,
          kind: AnswerKind.noRecognisedText,
          documentsSearched: value.length,
        );
      }
      return AssistantAnswer(
        text: notFoundMessage,
        kind: AnswerKind.noMatch,
        documentsSearched: value.length,
      );
    }

    return const AssistantAnswer(text: notFoundMessage, kind: AnswerKind.noMatch);
  }

  /// Applies deduplication, per-document diversity and the context budget.
  static List<RankedPassage> _select(List<RankedPassage> ranked) {
    final selected = <RankedPassage>[];
    final perDocument = <String, int>{};
    final usedPages = <String>{};
    var characters = 0;

    for (final candidate in ranked) {
      final passage = candidate.passage;

      // One passage per page. A page matching three times is one place to
      // look, not three.
      final page = '${passage.documentId}#${passage.pageIndex}';
      if (!usedPages.add(page)) continue;

      final fromDocument = perDocument[passage.documentId] ?? 0;
      if (fromDocument >= maxPassagesPerDocument) continue;

      if (characters + passage.text.length > contextCharacterBudget &&
          selected.isNotEmpty) {
        break;
      }

      selected.add(candidate);
      perDocument[passage.documentId] = fromDocument + 1;
      characters += passage.text.length;

      if (selected.length >= maxPassages) break;
    }

    return selected;
  }

  /// Builds the answer from the selected passages.
  ///
  /// The reply is the best passage verbatim. Every selected passage — the
  /// quoted one included — becomes a citation, so the user can see the answer
  /// in its original context rather than taking the quotation on trust.
  static AssistantAnswer _compose(
    List<RankedPassage> selected,
    int documentsSearched,
  ) {
    final best = selected.first;
    final top = best.score;

    return AssistantAnswer(
      text: best.passage.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
      kind: AnswerKind.grounded,
      confidence: _confidenceOf(best),
      documentsSearched: documentsSearched,
      citations: <AnswerCitation>[
        for (final candidate in selected)
          AnswerCitation(
            documentId: candidate.passage.documentId,
            documentTitle: candidate.passage.documentTitle,
            pageIndex: candidate.passage.pageIndex,
            snippet: PassageExtractor.citationSnippet(candidate.passage),
            matchedTerms: candidate.matchedTerms,
            // Relative to the best passage in this answer. An absolute figure
            // would invite comparison between answers, which these scores do
            // not support.
            relevance: top <= 0 ? 0 : (candidate.score / top).clamp(0, 1),
          ),
      ],
    );
  }

  /// How completely the quoted passage answered the question.
  ///
  /// Deliberately built only from things the engine actually knows: how much
  /// of the question the passage covered, and whether it carries the shape the
  /// question asked for. It says nothing about whether the document is right —
  /// which is why the UI labels these "match" rather than "confidence".
  static AnswerConfidence _confidenceOf(RankedPassage best) {
    if (best.coverage >= 0.999 && best.satisfiesIntent) {
      return AnswerConfidence.strong;
    }
    if (best.coverage >= 0.999 || best.satisfiesIntent) {
      return AnswerConfidence.partial;
    }
    return AnswerConfidence.weak;
  }

  @override
  FutureResult<List<String>> suggestedQuestions() async {
    try {
      final loaded = await _documents.getDocuments();
      if (loaded case Failed(:final failure)) return Failed(failure);

      final documents = (loaded as Success<List<Document>>).value
          .where((document) => document.hasText)
          .take(4)
          .toList(growable: false);

      if (documents.isEmpty) return const Success(<String>[]);

      final suggestions = <String>[];
      for (final document in documents) {
        final text = document.extractedText;
        final title = document.title;

        // Ask about what the page demonstrably contains. A suggestion that
        // returns nothing is worse than no suggestion — it teaches the user
        // the assistant does not work.
        if (PassageSignals.hasAmount(text)) {
          suggestions.add('How much is the $title?');
        } else if (PassageSignals.hasDate(text)) {
          suggestions.add('When is the $title due?');
        } else if (PassageSignals.hasContact(text)) {
          suggestions.add('What is the contact for the $title?');
        } else {
          suggestions.add('What does the $title say?');
        }
      }

      return Success(List<String>.unmodifiable(suggestions.take(4)));
    } catch (error, stackTrace) {
      return Failed(
        AssistantFailure(
          'Suggestions are unavailable.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---- Transcript ----------------------------------------------------------

  @override
  Stream<List<ChatMessage>> watchHistory() async* {
    yield _readHistory();
    yield* _history.watch().map((_) => _readHistory());
  }

  @override
  FutureResult<void> appendMessage(ChatMessage message) async {
    try {
      await _history.append(ChatMessageModel.fromEntity(message));
      return const Success<void>(null);
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    }
  }

  @override
  FutureResult<void> clearHistory() async {
    try {
      await _history.clear();
      return const Success<void>(null);
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    }
  }

  List<ChatMessage> _readHistory() => _history
      .readAll()
      .map((model) => model.toEntity())
      .toList(growable: false);
}
