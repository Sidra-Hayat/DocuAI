import 'dart:async';
import 'dart:math' as math;

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../domain/usecases/suggest_questions.dart';
import '../datasources/chat_history_local_data_source.dart';
import '../datasources/passage_extractor.dart';
import '../datasources/passage_ranker.dart';
import '../datasources/passage_summarizer.dart';
import '../datasources/question_analyzer.dart';
import '../datasources/shape_finder.dart';
import '../models/chat_message_model.dart';

/// One passage's contribution to an answer, before citations are merged.
typedef _Cited = ({Passage passage, double relevance, List<String> terms});

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

  static const String needsDocumentMessage =
      'Open the document you want and use the Summarise button there, or name '
      'it in your question — for example "summarise the tenancy agreement".';

  static const String documentHasNoTextMessage =
      "This document's text has not been recognised yet, so there is nothing "
      'for me to read. Recognition runs when a document is opened — give it a '
      'moment and ask again.';

  /// Sentences in a summary that was asked for briefly.
  static const int briefSummarySentences = 2;

  static const String nothingToExplainMessage =
      'Select some text and choose Explain, or paste the part you want me to '
      'look at.';

  static const String tooLittleTextMessage =
      'There is not enough recognised text in this document to summarise. It '
      'may have scanned poorly — try rescanning the page.';

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

      // Explaining reads a passage the user already has in front of them, so
      // it needs no target document — only the library, to say where else the
      // same terms appear.
      if (analyzed.mode == QuestionMode.explain) {
        return _explain(analyzed, documentId);
      }

      // Summarising and listing work on one document at a time, and neither
      // has query terms to rank with — so they resolve a target first and then
      // run their own ranker over the same extracted passages.
      if (analyzed.mode != QuestionMode.answer) {
        return _wholeDocument(analyzed, documentId);
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
      text: _flatten(best.passage.text),
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

  /// Says what a passage holds, and where else its terms appear.
  ///
  /// Not a paraphrase, and deliberately so: with no language model there is
  /// nothing to paraphrase with, and producing one would be the single thing
  /// this assistant promises never to do. What it can say honestly is what is
  /// *in* the passage — the dates, amounts, names and references it carries —
  /// and which other pages use the same words. Both are read off documents the
  /// user already has.
  FutureResult<AssistantAnswer> _explain(
    AnalyzedQuestion question,
    String? documentId,
  ) async {
    final passage = question.subject.trim();
    if (passage.isEmpty) {
      return const Success(
        AssistantAnswer(
          text: nothingToExplainMessage,
          kind: AnswerKind.unclearQuestion,
        ),
      );
    }

    final lines = <String>['This passage says:', '“${_flatten(passage)}”'];

    // What it contains, by shape. These are facts about the characters on the
    // page rather than an interpretation of them.
    final found = <String>[];
    for (final intent in const <QuestionIntent>[
      QuestionIntent.date,
      QuestionIntent.amount,
      QuestionIntent.identifier,
      QuestionIntent.contact,
      QuestionIntent.person,
    ]) {
      final values = PassageSignals.matches(intent, passage);
      if (values.isEmpty) continue;

      final label = ShapeFinder.labelFor(intent, plural: values.length != 1);
      found.add('• $label: ${values.take(6).join(', ')}');
    }

    if (found.isNotEmpty) {
      lines
        ..add('')
        ..add('It contains:')
        ..addAll(found);
    }

    // Where else the same words appear. The passage is used as a query, which
    // is the same retrieval every question goes through.
    final related = await _relatedTo(question, passage, documentId);
    if (related.isNotEmpty) {
      lines
        ..add('')
        ..add(
          related.length == 1
              ? 'One other place mentions the same terms:'
              : '${related.length} other places mention the same terms:',
        )
        ..addAll(
          related.map(
            (candidate) =>
                '• ${candidate.passage.documentTitle}, '
                'page ${candidate.passage.pageIndex + 1}',
          ),
        );
    }

    return Success(
      AssistantAnswer(
        text: lines.join('\n'),
        kind: AnswerKind.explanation,
        documentsSearched: related.isEmpty ? 0 : related.length,
        citations: _citationsByPage(<_Cited>[
          for (final candidate in related)
            (
              passage: candidate.passage,
              relevance: candidate.coverage,
              terms: candidate.matchedTerms,
            ),
        ]),
      ),
    );
  }

  /// Passages elsewhere that use the same words as [passage].
  Future<List<RankedPassage>> _relatedTo(
    AnalyzedQuestion question,
    String passage,
    String? documentId,
  ) async {
    final asQuery = QuestionAnalyzer.analyze(passage);
    if (asQuery.isEmpty) return const <RankedPassage>[];

    final candidates = await _candidates(asQuery, documentId);
    if (candidates case Success(:final value)) {
      final passages = <Passage>[
        for (final document in value.documents)
          ...PassageExtractor.extract(document),
      ];

      final ranked = PassageRanker.rank(
        question: asQuery,
        passages: passages,
        documentPriors: value.priors,
      );

      // The selection ranks first against itself, which tells the user nothing
      // they are not already looking at. Excluded by equality, not by
      // containment: a *longer* sentence that quotes the same words is the
      // most useful result there is, and dropping those left nothing at all.
      final flattened = _flatten(passage).toLowerCase();
      return _select(
        ranked
            .where(
              (candidate) =>
                  _flatten(candidate.passage.text).toLowerCase() != flattened,
            )
            .toList(growable: false),
      );
    }

    return const <RankedPassage>[];
  }

  // ---- Whole-document modes ------------------------------------------------

  /// Summarising and listing, which both read one document end to end.
  ///
  /// The stages are unchanged — OCR text, extracted passages, a ranking, an
  /// answer with citations. What differs is that neither request carries query
  /// terms, so the document is resolved first and the ranking is over the whole
  /// of it rather than against a question.
  FutureResult<AssistantAnswer> _wholeDocument(
    AnalyzedQuestion question,
    String? documentId,
  ) async {
    final resolved = await _resolveTarget(question, documentId);
    if (resolved case Failed(:final failure)) return Failed(failure);

    final document = (resolved as Success<Document?>).value;
    if (document == null) {
      // Two different dead ends. Nothing named means the request never said
      // which document; something named that matched nothing is a search that
      // came back empty, and saying so is what lets the user correct the name.
      return Success(
        question.subjectTerms.isEmpty
            ? const AssistantAnswer(
                text: needsDocumentMessage,
                kind: AnswerKind.needsDocument,
              )
            : AssistantAnswer(
                text:
                    'I could not find a document matching '
                    '"${question.subjectTerms.join(' ')}".',
                kind: AnswerKind.noMatch,
              ),
      );
    }

    if (!document.hasText) {
      return const Success(
        AssistantAnswer(
          text: documentHasNoTextMessage,
          kind: AnswerKind.noRecognisedText,
          documentsSearched: 1,
        ),
      );
    }

    final passages = PassageExtractor.extract(document);

    // Only summary and find reach here; `ask` routes the answer mode away
    // above, before a document is ever resolved.
    return Success(
      question.mode == QuestionMode.summary
          ? _composeSummary(document, passages, brief: question.brief)
          : _composeFindings(question.intent, document, passages),
    );
  }

  /// Which document a whole-document request is about.
  ///
  /// Null when the request named none — the caller turns that into advice
  /// rather than an error, because "summarise this document" from the
  /// library-wide conversation is a reasonable thing to type and only needs
  /// pointing at a document.
  FutureResult<Document?> _resolveTarget(
    AnalyzedQuestion question,
    String? documentId,
  ) async {
    if (documentId != null) {
      return switch (await _documents.getDocument(documentId)) {
        Failed(:final failure) => Failed(failure),
        Success(:final value) => Success<Document?>(value),
      };
    }

    if (question.subjectTerms.isEmpty) return const Success<Document?>(null);

    // Whatever is left after the request vocabulary is the user naming the
    // document — "summarise the tenancy agreement" — and search is precisely
    // the stage that turns a name into a document.
    final found = await _search.search(question.subjectTerms.join(' '));
    return switch (found) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success<Document?>(
        value.isEmpty ? null : value.first.document,
      ),
    };
  }

  /// The document's own sentences, chosen to stand for the whole of it.
  static AssistantAnswer _composeSummary(
    Document document,
    List<Passage> passages, {
    bool brief = false,
  }) {
    final sentences = PassageSummarizer.summarize(
      passages,
      // A brief summary is two sentences, not five. Asked for "briefly", a
      // wall of text is the wrong answer however well chosen its sentences.
      maxSentences: brief ? briefSummarySentences : PassageSummarizer.maxSentences,
      characterBudget: brief
          ? contextCharacterBudget ~/ 2
          : contextCharacterBudget,
    );

    if (sentences.isEmpty) {
      return const AssistantAnswer(
        text: tooLittleTextMessage,
        kind: AnswerKind.noMatch,
        documentsSearched: 1,
      );
    }

    return AssistantAnswer(
      // Bulleted rather than run together: these are separate statements
      // pulled from separate places, and joining them into a paragraph would
      // imply a connecting argument nobody wrote.
      text: sentences
          .map((sentence) => '• ${_flatten(sentence.passage.text)}')
          .join('\n'),
      kind: AnswerKind.summary,
      documentsSearched: 1,
      citations: _citationsByPage(<_Cited>[
        for (final sentence in sentences)
          (
            passage: sentence.passage,
            relevance: sentence.weight,
            terms: sentence.highlights,
          ),
      ]),
    );
  }

  /// Every value of one shape, in the order the document states them.
  static AssistantAnswer _composeFindings(
    QuestionIntent intent,
    Document document,
    List<Passage> passages,
  ) {
    final findings = ShapeFinder.find(intent, passages);

    if (findings.isEmpty) {
      return AssistantAnswer(
        text:
            'I could not find any '
            '${ShapeFinder.labelFor(intent, plural: true)} in '
            '${document.title}.',
        kind: AnswerKind.noMatch,
        documentsSearched: 1,
      );
    }

    final label = ShapeFinder.labelFor(intent, plural: findings.length != 1);

    return AssistantAnswer(
      text:
          'Found ${findings.length} $label:\n'
          '${findings.map((finding) => '• ${finding.value}').join('\n')}',
      kind: AnswerKind.extraction,
      // A currency symbol beside a number is a fact about the page; two
      // capitalised words is a convention that headings share with names. The
      // chip says so rather than claiming the same certainty for both.
      confidence: intent == QuestionIntent.person
          ? AnswerConfidence.partial
          : AnswerConfidence.strong,
      documentsSearched: 1,
      citations: _citationsByPage(<_Cited>[
        for (final finding in findings)
          (
            passage: finding.passage,
            relevance: 1,
            // The values themselves, so the source card shows what was read
            // off that page rather than which words happened to match.
            terms: <String>[finding.value],
          ),
      ]),
    );
  }

  /// Collapses per-sentence provenance into one citation per page.
  ///
  /// A summary quoting three sentences from page one is one place to look, not
  /// three, and the source card renders a single snippet per document anyway —
  /// so repeated pages would only produce "Page 1, Page 1, Page 2" under it.
  static List<AnswerCitation> _citationsByPage(List<_Cited> cited) {
    final byPage = <String, AnswerCitation>{};

    for (final entry in cited) {
      final passage = entry.passage;
      final key = '${passage.documentId}#${passage.pageIndex}';
      final existing = byPage[key];

      byPage[key] = existing == null
          ? AnswerCitation(
              documentId: passage.documentId,
              documentTitle: passage.documentTitle,
              pageIndex: passage.pageIndex,
              snippet: PassageExtractor.citationSnippet(passage),
              matchedTerms: List<String>.unmodifiable(entry.terms),
              relevance: entry.relevance.clamp(0, 1),
            )
          : existing.copyWith(
              matchedTerms: List<String>.unmodifiable(<String>{
                ...existing.matchedTerms,
                ...entry.terms,
              }),
              relevance: math.max(existing.relevance, entry.relevance)
                  .clamp(0, 1)
                  .toDouble(),
            );
    }

    return List<AnswerCitation>.unmodifiable(byPage.values);
  }

  /// The one place a passage becomes something to read.
  ///
  /// Every answer this class composes — a quoted reply, a summary line, an
  /// explained selection — passes through here, and markers are removed at
  /// this point and nowhere earlier. Retrieval never sees the change: the
  /// tokeniser already splits on non-alphanumerics, so `**total**` and `total`
  /// have always been the same term to BM25 and to passage ranking. Stripping
  /// before extraction would move `Passage.start`/`end` off the text they
  /// index into and quietly point every citation at the wrong span.
  static String _flatten(String text) => Markup.toInlineText(text);

  @override
  FutureResult<List<String>> suggestedQuestions({String? documentId}) async {
    try {
      if (documentId != null) {
        final loaded = await _documents.getDocument(documentId);
        return switch (loaded) {
          Failed(:final failure) => Failed(failure),
          Success(:final value) => Success(_questionsAbout(value)),
        };
      }

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

  /// What is worth asking of one particular document.
  ///
  /// Offered only where the page demonstrably carries the shape, using the same
  /// signals the finder will use to answer. A chip that returns "I could not
  /// find any names" is worse than no chip — it teaches the user the assistant
  /// does not work, when in fact it was asked for something that is not there.
  static List<String> _questionsAbout(Document document) {
    if (!document.hasText) return const <String>[];

    final text = document.extractedText;

    return List<String>.unmodifiable(<String>[
      // Always available: any recognised text can be summarised, and this is
      // the question people arrive with.
      DocumentQuestions.summarise,
      if (PassageSignals.hasDate(text)) DocumentQuestions.dates,
      if (PassageSignals.hasAmount(text)) DocumentQuestions.amounts,
      if (PassageSignals.hasProperName(text)) DocumentQuestions.names,
      if (PassageSignals.hasContact(text)) DocumentQuestions.contact,
      if (PassageSignals.hasIdentifier(text)) DocumentQuestions.references,
    ].take(4));
  }

  // ---- Transcript ----------------------------------------------------------

  @override
  Stream<List<Conversation>> watchConversations({String? documentId}) =>
      _watch(() {
        final all = _history
            .readAll()
            .map((model) => model.toEntity())
            .where(
              (message) =>
                  documentId == null || message.documentId == documentId,
            )
            .toList(growable: false);

        return Conversation.from(all);
      });

  @override
  Stream<List<ChatMessage>> watchHistory({required String conversationId}) =>
      _watch(
        () => _history
            .readAll()
            .map((model) => model.toEntity())
            .where((message) => message.conversation == conversationId)
            .toList(growable: false),
      );

  /// Re-reads [read] on every change to the box.
  ///
  /// Subscribes before the first read, for the reason the document library
  /// does: a generator that yields a snapshot and then subscribes misses
  /// anything written in between, and Hive's broadcast feed buffers nothing.
  Stream<T> _watch<T>(T Function() read) {
    final controller = StreamController<T>();
    StreamSubscription<void>? changes;

    void emit() {
      try {
        controller.add(read());
      } on CacheException catch (error, stackTrace) {
        controller.addError(
          StorageFailure(error.message, cause: error),
          stackTrace,
        );
      }
    }

    controller.onListen = () {
      changes = _history.watch().listen(
        (_) => emit(),
        onError: controller.addError,
        onDone: () {
          controller.addError(
            const StorageFailure('The conversation stopped updating.'),
            StackTrace.current,
          );
          controller.close();
        },
      );

      emit();
    };

    controller.onCancel = () async {
      await changes?.cancel();
      changes = null;
    };

    return controller.stream;
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
  FutureResult<void> deleteConversation(String conversationId) async {
    try {
      await _history.deleteConversation(conversationId);
      return const Success<void>(null);
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    }
  }


}
