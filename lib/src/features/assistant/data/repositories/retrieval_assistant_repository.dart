import 'dart:async';
import 'dart:math' as math;

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/entities/search_hit.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/assistant_intent.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../domain/usecases/suggest_questions.dart';
import '../datasources/answer_phrasing.dart';
import '../datasources/chat_history_local_data_source.dart';
import '../datasources/document_topics.dart';
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

  /// Said when a document has text but nothing that describes it.
  static const String cannotExplainMessage =
      "I couldn't extract enough readable text from this document to explain "
      'it.';

  /// Said when a document-shaped action arrives with no document.
  static const String openADocumentMessage =
      'Open the document you want first — this works on one document at a '
      'time.';

  @override
  FutureResult<AssistantAnswer> run(
    AssistantIntent intent, {
    String? documentId,
  }) async {
    try {
      return switch (intent) {
        AskQuestion(:final question) => await _answerQuestion(
          question,
          documentId,
        ),
        SummarizeDocument(:final brief) => await _onOneDocument(
          documentId,
          (document, chosen) async => _composeSummary(
            document,
            PassageExtractor.extract(document),
            brief: brief,
          ),
        ),
        ExplainDocument() => await _onOneDocument(documentId, _explainDocument),
        ExplainSelection(:final text) => await _explainPassage(
          text,
          documentId,
        ),
        FindInformation(:final kind) => await _findInformation(
          kind,
          documentId,
        ),
      };
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

  @override
  FutureResult<AssistantAnswer> ask(String question, {String? documentId}) =>
      run(AskQuestion(question), documentId: documentId);

  /// A typed question: the only input that is parsed.
  Future<Result<AssistantAnswer>> _answerQuestion(
    String question,
    String? documentId,
  ) async {
    final analyzed = QuestionAnalyzer.analyze(question);
    if (analyzed.isEmpty) {
      return const Success(
        AssistantAnswer(text: unclearMessage, kind: AnswerKind.unclearQuestion),
      );
    }

    if (analyzed.mode == QuestionMode.explain) {
      return _routeTypedExplain(analyzed, documentId);
    }

    // Summarising and listing work on one document at a time, and neither has
    // query terms to rank with — so they resolve a target first and then run
    // their own ranker over the same extracted passages.
    if (analyzed.mode != QuestionMode.answer) {
      return _wholeDocument(analyzed, documentId);
    }

    return _retrieve(analyzed, documentId);
  }

  /// The ordinary retrieval path: BM25, then passage ranking, then a quote.
  ///
  /// With one rescue on the way out. A question can name a shape *and* narrow
  /// it — "who is mentioned in the internship report" asks for names and says
  /// where — and narrowing sends it down this path, where the words "mentioned"
  /// and "report" appear on no page and nothing matches. Rather than report
  /// that a document full of names contains none, a failed answer to a question
  /// that asked for a *kind* of thing falls through to listing that kind.
  ///
  /// Only ever on failure, so it cannot dilute a question retrieval did answer.
  Future<Result<AssistantAnswer>> _retrieve(
    AnalyzedQuestion analyzed,
    String? documentId,
  ) async {
    final candidates = await _candidates(analyzed, documentId);
    if (candidates case Failed(:final failure)) return Failed(failure);

    final found = (candidates as Success<
      ({List<Document> documents, Map<String, double> priors})
    >).value;
    final answer = await _answerFrom(analyzed, found);

    if (answer.kind != AnswerKind.noMatch ||
        analyzed.intent == QuestionIntent.general) {
      return Success(answer);
    }

    // Scoped to whichever document the question pointed at, when it pointed at
    // one, so "names in the internship report" does not answer with names from
    // the electricity bill.
    final scope = documentId ?? await _bestMatchFor(analyzed);
    final listed = await _findInformation(_kindFor(analyzed.intent), scope);

    return switch (listed) {
      Success(value: final AssistantAnswer value)
          when value.kind == AnswerKind.extraction =>
        Success(value),
      // The listing found nothing either. The original answer is the honest
      // one: it says the information is not there, which is true.
      _ => Success(answer),
    };
  }

  /// The document a question's own words point at, if any.
  Future<String?> _bestMatchFor(AnalyzedQuestion question) async {
    if (question.subjectTerms.isEmpty) return null;

    final found = await _search.search(question.subjectTerms.join(' '));
    return found is Success<List<SearchHit>> && found.value.isNotEmpty
        ? found.value.first.document.id
        : null;
  }

  /// What a typed "explain …" actually asked for.
  ///
  /// Three different requests wear the same verb, and telling them apart is the
  /// whole of the defect this method exists to close. The old code took
  /// everything after the verb and treated it as a passage to be explained,
  /// which is right for exactly one of the three and produced, for the other
  /// two, the query quoted back as though it were content:
  ///
  /// ```
  /// This passage says:
  /// “this document”
  /// ```
  ///
  /// The rule, in order:
  ///
  ///  * **Nothing named beyond the document itself** — "explain this document",
  ///    "explain this", "explain the page". The subject is the document, so the
  ///    document gets explained. This is also the reason the *button* no longer
  ///    goes through here at all: it knew that already.
  ///  * **Marked off by a colon, or long enough to be prose** — someone handed
  ///    over a passage. Explain the passage.
  ///  * **Anything else** — "explain its features", "explain the standing
  ///    charge". That is a question about a topic, and it goes down the same
  ///    retrieval path as any other question. If the documents do not cover it,
  ///    the answer is that they do not cover it, which is the truth and is
  ///    never the words of the question read back.
  Future<Result<AssistantAnswer>> _routeTypedExplain(
    AnalyzedQuestion analyzed,
    String? documentId,
  ) async {
    final subject = analyzed.subject.trim();
    if (subject.isEmpty) {
      return const Success(
        AssistantAnswer(
          text: nothingToExplainMessage,
          kind: AnswerKind.unclearQuestion,
        ),
      );
    }

    if (QuestionAnalyzer.namesOnlyTheDocument(subject)) {
      return _onOneDocument(documentId, _explainDocument);
    }

    if (analyzed.subjectIsDelimited || _readsAsProse(subject)) {
      return _explainPassage(subject, documentId);
    }

    final retrieved = await _retrieve(analyzed, documentId);

    // "Explain the second section" names a part of the document the app cannot
    // see — there is no section index — so retrieval finds nothing. Explaining
    // the document answers the question that was actually being asked.
    //
    // Which document, when none is open, is the same question "what is the
    // internship report about?" already answers: the one the user named. That
    // is resolved by searching for the subject, so a subject naming nothing in
    // the library resolves to nothing and the not-found answer stands — the
    // fallback can reach a document the user pointed at, and never invents one.
    if (retrieved is Success<AssistantAnswer> &&
        retrieved.value.kind == AnswerKind.noMatch) {
      final target = documentId ?? await _bestMatchFor(analyzed);
      if (target != null) {
        // Named by the user rather than open in front of them, so the answer
        // says which document it read. "This document" is only unambiguous on
        // a screen that is showing one.
        return _onOneDocument(
          target,
          (document, _) => _explainDocument(document, documentId == null),
        );
      }
    }

    return retrieved;
  }

  /// Long enough that someone pasted it rather than typed a request.
  ///
  /// A backstop for a selection pasted without the colon the Explain action
  /// puts there. Deliberately generous — being wrong here costs a passage
  /// explained as a question, which still answers from the document.
  static bool _readsAsProse(String subject) =>
      subject.trim().split(RegExp(r'\s+')).length >= 8;

  /// Runs [body] against the document the conversation is about.
  ///
  /// Summarising and explaining genuinely need one document — there is no such
  /// thing as the summary of a library — but "needs one document" is not the
  /// same as "needs the user to go and open one". Asked from the Assistant tab,
  /// "what is this document about?" used to answer
  ///
  /// ```
  /// Open the document you want first — this works on one document at a time.
  /// ```
  ///
  /// which is the app declining to answer a question it has everything it needs
  /// to answer. The user is on the Assistant screen precisely because they were
  /// not thinking in terms of which document holds what.
  ///
  /// So when the conversation names no document, the most recently updated
  /// readable one is used — the document they were last working on, which is
  /// what "this document" means to someone who has just come from the library.
  /// The answer then *names* what it read, so a wrong guess is visible in the
  /// first line rather than mistaken for a fact about something else.
  ///
  /// [body] is told which happened, because an answer about the document on
  /// screen should not announce a title the user is already looking at.
  Future<Result<AssistantAnswer>> _onOneDocument(
    String? documentId,
    Future<AssistantAnswer> Function(Document document, bool chosen) body,
  ) async {
    if (documentId == null) {
      final chosen = await _mostRecentReadable();
      if (chosen case Failed(:final failure)) return Failed(failure);

      final document = (chosen as Success<Document?>).value;
      // Nothing readable to fall back to. `_emptyHanded` tells an empty library
      // apart from one whose text has not been recognised, which send the user
      // to completely different places.
      if (document == null) return Success(await _emptyHanded());

      return Success(await body(document, true));
    }

    final loaded = await _documents.getDocument(documentId);
    if (loaded case Failed(:final failure)) return Failed(failure);

    final document = (loaded as Success<Document>).value;
    if (!document.hasText) {
      return const Success(
        AssistantAnswer(
          text: documentHasNoTextMessage,
          kind: AnswerKind.noRecognisedText,
          documentsSearched: 1,
        ),
      );
    }

    return Success(await body(document, false));
  }

  /// The document the user was last working on, or null if none can be read.
  ///
  /// Sorted here rather than trusted from the repository. `readAll` does return
  /// newest-first today, but "which document did the assistant pick" is a
  /// user-visible decision, and one that quietly depended on a sort order
  /// declared in another layer would be one refactor away from picking the
  /// oldest document instead.
  FutureResult<Document?> _mostRecentReadable() async {
    final loaded = await _documents.getDocuments();
    if (loaded case Failed(:final failure)) return Failed(failure);

    final readable =
        (loaded as Success<List<Document>>).value
            .where((document) => document.hasText)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return Success<Document?>(readable.isEmpty ? null : readable.first);
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
          for (final hit in value.take(maxDocuments))
            hit.document.id: hit.score,
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

    return const AssistantAnswer(
      text: notFoundMessage,
      kind: AnswerKind.noMatch,
    );
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
  Future<Result<AssistantAnswer>> _explainPassage(
    String selection,
    String? documentId,
  ) async {
    final passage = selection.trim();
    if (passage.isEmpty) {
      return const Success(
        AssistantAnswer(
          text: nothingToExplainMessage,
          kind: AnswerKind.unclearQuestion,
        ),
      );
    }

    // A selection that turns out to name only the document is the document
    // asking to be explained. The reader cannot produce one — it passes what
    // was highlighted — but a typed "Explain: this document" can, and quoting
    // those two words back is the defect this whole change is about.
    if (QuestionAnalyzer.namesOnlyTheDocument(passage)) {
      return _onOneDocument(documentId, _explainDocument);
    }

    // The selection itself, and nothing announcing it. It used to open "This
    // passage says:" above the user's own selection, which is the assistant
    // reading back what the user had just highlighted — a sentence that told
    // them nothing they did not already know.
    final lines = <String>['“${_flatten(passage)}”'];

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
      found.add(
        '• ${AnswerPhrasing.capitalise(label)}: '
        '${values.take(6).join(', ')}',
      );
    }

    if (found.isNotEmpty) {
      lines
        ..add('')
        ..add('What it records:')
        ..addAll(found);
    }

    // Where else the same words appear. The passage is used as a query, which
    // is the same retrieval every question goes through.
    final related = await _relatedTo(passage, documentId);
    if (related.isNotEmpty) {
      lines
        ..add('')
        ..add(
          related.length == 1
              ? 'The same wording appears in one other place:'
              : 'The same wording appears in '
                    '${AnswerPhrasing.count(related.length, 'other place', 'other places')}:',
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

  // ---- Actions -------------------------------------------------------------

  /// What the document is, and what it covers.
  ///
  /// Composed rather than quoted, and this is the one place that word is used
  /// honestly: the *scaffolding* is written here — "This document is called",
  /// "What it covers" — and every fact between those words was read off the
  /// page. The topics are the document's own headings where it has them, and
  /// its most representative sentences where it does not.
  ///
  /// It is worth being plain about what this is not. Without a language model
  /// there is no paraphrase available, so this does not read like a person
  /// describing the document in their own words. It reads like the document's
  /// table of contents plus the facts it carries — which is a genuine answer to
  /// "what is this?", and unlike a paraphrase it cannot be wrong.
  Future<AssistantAnswer> _explainDocument(
    Document document, [
    bool chosen = false,
  ]) async {
    final passages = PassageExtractor.extract(document);
    final outline = DocumentTopics.of(document);

    if (outline.isEmpty) {
      return const AssistantAnswer(
        text: cannotExplainMessage,
        kind: AnswerKind.noMatch,
        documentsSearched: 1,
      );
    }

    final topics = outline.topics;
    final lines = <String>[];

    // Which document is being described. "This document" is right when the user
    // is looking at one and wrong when the assistant picked it — there, naming
    // it is the difference between an answer and a claim about something
    // unidentified.
    final subject = chosen ? '“${document.title}”' : 'This document';

    if (outline.fromHeadings) {
      // A document that divided itself into sections has already answered the
      // question. Listing those sections in one sentence is the closest an
      // extractive assistant honestly gets to describing a document — and every
      // word of it was typed by whoever wrote the thing.
      lines.add(
        '$subject covers '
        '${AnswerPhrasing.list(topics.map((topic) => topic.text))}.',
      );
    } else {
      // No headings — a scan, almost always. The opening line is quoted rather
      // than paraphrased, because paraphrasing it would mean inventing the
      // paraphrase.
      lines.add(
        '$subject is about '
        '“${AnswerPhrasing.withoutTrailingStop(topics.first.text)}”.',
      );

      if (topics.length > 1) {
        lines
          ..add('')
          ..add('It also covers:')
          ..addAll(topics.skip(1).map((topic) => '• ${topic.text}'));
      }
    }

    // What kinds of fact it carries, counted rather than reprinted. Listing
    // them is what "Find important information" is for; an explanation that
    // repeated every figure on the page would be the page again.
    final carries = <String>[
      for (final intent in _digestIntents)
        if (ShapeFinder.find(intent, passages, maxFindings: 20) case final found
            when found.isNotEmpty)
          AnswerPhrasing.count(
            found.length,
            ShapeFinder.labelFor(intent, plural: false),
            ShapeFinder.labelFor(intent, plural: true),
          ),
    ];

    if (carries.isNotEmpty) {
      lines
        ..add('')
        ..add('It records ${AnswerPhrasing.list(carries)}.');
    }

    // One citation per page a topic came from, so the explanation can be
    // checked against the pages it was built out of.
    final firstOnPage = <int, Passage>{};
    for (final passage in passages) {
      firstOnPage.putIfAbsent(passage.pageIndex, () => passage);
    }

    return AssistantAnswer(
      text: lines.join('\n'),
      kind: AnswerKind.explanation,
      documentsSearched: 1,
      citations: _citationsByPage(<_Cited>[
        for (final topic in topics)
          if (firstOnPage[topic.pageIndex] case final passage?)
            (passage: passage, relevance: 1, terms: <String>[topic.text]),
      ]),
    );
  }

  /// A shape's label at the start of a line.
  static String _capitalise(String label) =>
      '${label[0].toUpperCase()}${label.substring(1)}';

  /// The shapes a digest reports, in the order they are worth reading.
  static const List<QuestionIntent> _digestIntents = <QuestionIntent>[
    QuestionIntent.date,
    QuestionIntent.amount,
    QuestionIntent.person,
    QuestionIntent.contact,
    QuestionIntent.identifier,
    QuestionIntent.place,
  ];

  /// The listing that answers a question of this shape.
  ///
  /// The inverse of [_intentFor]. It exists so a *typed* request reaches the
  /// same extraction the button does — the quick actions are shortcuts, not a
  /// second engine.
  static InformationKind _kindFor(QuestionIntent intent) => switch (intent) {
    QuestionIntent.person => InformationKind.names,
    QuestionIntent.date => InformationKind.dates,
    QuestionIntent.amount => InformationKind.amounts,
    QuestionIntent.place => InformationKind.locations,
    QuestionIntent.identifier => InformationKind.references,
    QuestionIntent.contact => InformationKind.contacts,
    QuestionIntent.general => InformationKind.important,
  };

  /// Names the documents a request could have meant.
  ///
  /// Better than "open the document you want": the user is on the Assistant
  /// screen precisely because they were not thinking in terms of which document
  /// holds what, and listing three titles is a shorter route to an answer than
  /// making them go and find one.
  Future<AssistantAnswer> _askWhichDocument(AnalyzedQuestion question) async {
    // Something was named and matched nothing — a different problem, and one
    // the user fixes by correcting the name rather than by picking from a list.
    if (question.subjectTerms.isNotEmpty) {
      return AssistantAnswer(
        text:
            'I could not find a document matching '
            '"${question.subjectTerms.join(' ')}".',
        kind: AnswerKind.noMatch,
      );
    }

    final loaded = await _documents.getDocuments();
    final readable = loaded is Success<List<Document>>
        ? loaded.value.where((document) => document.hasText).toList()
        : const <Document>[];

    if (readable.isEmpty) {
      return const AssistantAnswer(
        text: emptyLibraryMessage,
        kind: AnswerKind.emptyLibrary,
      );
    }

    final named = readable.take(5).map((document) => document.title);

    return AssistantAnswer(
      text:
          'Which document did you mean? You can ask about '
          '${AnswerPhrasing.list(named)}.',
      kind: AnswerKind.needsDocument,
    );
  }

  static QuestionIntent _intentFor(InformationKind kind) => switch (kind) {
    InformationKind.names => QuestionIntent.person,
    InformationKind.dates => QuestionIntent.date,
    InformationKind.amounts => QuestionIntent.amount,
    InformationKind.locations => QuestionIntent.place,
    InformationKind.references => QuestionIntent.identifier,
    InformationKind.contacts => QuestionIntent.contact,
    // Handled before this is reached — a digest is every shape, not one.
    InformationKind.important => QuestionIntent.general,
  };

  /// Pulls every value of one kind — or of all of them — off the pages.
  ///
  /// Reads shapes rather than words, which is the entire reason these are
  /// actions and not questions: no page writes "dates" beside its dates, so
  /// ranking by term coverage scores zero everywhere and answers "I could not
  /// find that" about values that are plainly there.
  ///
  /// Scoped to the open document when there is one. With none — the Assistant
  /// tab's own conversation — it reads the most recent documents that have
  /// text, because "find every date I have" is a reasonable thing to want and
  /// refusing it would be a worse answer than a bounded one.
  Future<Result<AssistantAnswer>> _findInformation(
    InformationKind kind,
    String? documentId,
  ) async {
    final List<Document> documents;
    final String scope;

    if (documentId != null) {
      final loaded = await _documents.getDocument(documentId);
      if (loaded case Failed(:final failure)) return Failed(failure);

      final document = (loaded as Success<Document>).value;
      if (!document.hasText) {
        return const Success(
          AssistantAnswer(
            text: documentHasNoTextMessage,
            kind: AnswerKind.noRecognisedText,
            documentsSearched: 1,
          ),
        );
      }

      documents = <Document>[document];
      scope = document.title;
    } else {
      final loaded = await _documents.getDocuments();
      if (loaded case Failed(:final failure)) return Failed(failure);

      documents = (loaded as Success<List<Document>>).value
          .where((document) => document.hasText)
          .take(maxDocuments)
          .toList(growable: false);
      scope = 'your documents';
    }

    if (documents.isEmpty) return Success(await _emptyHanded());

    final passages = <Passage>[
      for (final document in documents) ...PassageExtractor.extract(document),
    ];

    if (kind == InformationKind.important) {
      return Success(_composeDigest(passages, scope, documents.length));
    }

    final intent = _intentFor(kind);
    return Success(
      _composeFindings(
        intent,
        ShapeFinder.find(intent, passages),
        scope,
        documents.length,
      ),
    );
  }

  /// Everything worth knowing, grouped by what kind of thing it is.
  static AssistantAnswer _composeDigest(
    List<Passage> passages,
    String scope,
    int documentsSearched,
  ) {
    final sections = <String>[];
    final cited = <_Cited>[];

    for (final intent in _digestIntents) {
      final findings = ShapeFinder.find(intent, passages, maxFindings: 6);
      if (findings.isEmpty) continue;

      sections.add(
        '${_capitalise(ShapeFinder.labelFor(intent, plural: true))}\n'
        '${findings.map((finding) => '• ${finding.value}').join('\n')}',
      );

      for (final finding in findings) {
        cited.add((
          passage: finding.passage,
          relevance: 1,
          terms: <String>[finding.value],
        ));
      }
    }

    if (sections.isEmpty) {
      return AssistantAnswer(
        text:
            'I could not find any dates, amounts, names or reference numbers '
            'in $scope.',
        kind: AnswerKind.noMatch,
        documentsSearched: documentsSearched,
      );
    }

    return AssistantAnswer(
      text: 'Here is what stands out in $scope:\n\n${sections.join('\n\n')}',
      kind: AnswerKind.extraction,
      // A digest mixes a currency figure, which is a fact about the page, with
      // a capitalised pair of words, which is a convention headings share with
      // names. Partial is the honest reading of the set.
      confidence: AnswerConfidence.partial,
      documentsSearched: documentsSearched,
      citations: _citationsByPage(cited),
    );
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
      // Nothing to narrow to. Asked from inside a document this cannot happen;
      // asked from the Assistant tab it is the ordinary case, and it used to
      // end here with "open the document you want" — which made every listing
      // question typed from the main screen a dead end, while the same request
      // made with a button worked. The button was right: a request for every
      // date does not need a document, it needs the library.
      if (question.mode == QuestionMode.find) {
        return _findInformation(_kindFor(question.intent), null);
      }

      // Something was named and matched nothing. Falling back to the newest
      // document here would answer about the wrong one under a title the user
      // never asked for, so this reports the miss instead.
      if (question.subjectTerms.isNotEmpty) {
        return Success(await _askWhichDocument(question));
      }

      // Nothing was named at all — "summarise my latest document", "what are
      // the important points?". That is a whole-document request about the
      // document the user was last working on, and answering it is what
      // [_onOneDocument] does. Only a summary reaches here: the listing modes
      // went library-wide above, and explain never enters this method.
      return _onOneDocument(
        null,
        (target, chosen) async => _composeSummary(
          target,
          PassageExtractor.extract(target),
          brief: question.brief,
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

    // Only summary and find reach here; the question path routes the answer
    // mode away above, before a document is ever resolved.
    if (question.mode == QuestionMode.summary) {
      return Success(
        _composeSummary(document, passages, brief: question.brief),
      );
    }

    // A listing request that named no shape — "find important information" —
    // is the digest, the same answer the button produces.
    if (question.intent == QuestionIntent.general) {
      return Success(_composeDigest(passages, document.title, 1));
    }

    return Success(
      _composeFindings(
        question.intent,
        ShapeFinder.find(question.intent, passages),
        document.title,
        1,
      ),
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
      maxSentences: brief
          ? briefSummarySentences
          : PassageSummarizer.maxSentences,
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
      //
      // The line above them says what they are. A reply that opens straight
      // into a bullet reads like a fragment of something rather than an answer
      // to what was asked.
      text:
          '${brief ? '“${document.title}” in short:' : 'The main points of '
                    '“${document.title}”:'}\n\n'
          '${sentences.map((sentence) => '• ${_flatten(sentence.passage.text)}').join('\n')}',
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

  /// Every value of one shape, in the order the pages state them.
  ///
  /// [scope] names what was read — a document's title, or "your documents" when
  /// the request was not about one in particular — so a fruitless search says
  /// where it looked.
  static AssistantAnswer _composeFindings(
    QuestionIntent intent,
    List<ShapeFinding> findings,
    String scope,
    int documentsSearched,
  ) {
    if (findings.isEmpty) {
      return AssistantAnswer(
        text:
            'I could not find any '
            '${ShapeFinder.labelFor(intent, plural: true)} in $scope.',
        kind: AnswerKind.noMatch,
        documentsSearched: documentsSearched,
      );
    }

    return AssistantAnswer(
      text:
          'I found '
          '${AnswerPhrasing.count(findings.length, ShapeFinder.labelFor(intent, plural: false), ShapeFinder.labelFor(intent, plural: true))} '
          'in $scope:\n'
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
              relevance: math
                  .max(existing.relevance, entry.relevance)
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

      final readable =
          (loaded as Success<List<Document>>).value
              .where((document) => document.hasText)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (readable.isEmpty) return const Success(<String>[]);

      return Success(_questionsAboutTheLibrary(readable));
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

  /// What is worth asking of the library as a whole.
  ///
  /// [readable] arrives newest-first and every entry has recognised text.
  ///
  /// Each suggestion is checked against the library before it is offered, using
  /// the same signals that will answer it — so the names chip appears only if a
  /// name survives the conservative filter that the answer will apply, and the
  /// dates chip only if a date is written somewhere. The two openers need no
  /// check: any readable document can be summarised, and any can be described.
  static List<String> _questionsAboutTheLibrary(List<Document> readable) {
    // Read once. `extractedText` walks every page of every document, and asking
    // four separate questions of it would walk the library four times.
    final corpus = readable
        .map((document) => document.extractedText)
        .join('\n');

    return List<String>.unmodifiable(
      <String>[
        LibraryQuestions.summariseLatest,
        LibraryQuestions.about(readable.first.title),
        if (PassageSignals.hasDate(corpus)) LibraryQuestions.dates,
        if (PassageSignals.hasProperName(corpus)) LibraryQuestions.names,
        if (PassageSignals.hasAmount(corpus)) LibraryQuestions.amounts,
      ].take(4),
    );
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

    return List<String>.unmodifiable(
      <String>[
        // Always available: any recognised text can be summarised, and this is
        // the question people arrive with.
        DocumentQuestions.summarise,
        if (PassageSignals.hasDate(text)) DocumentQuestions.dates,
        if (PassageSignals.hasAmount(text)) DocumentQuestions.amounts,
        if (PassageSignals.hasProperName(text)) DocumentQuestions.names,
        if (PassageSignals.hasContact(text)) DocumentQuestions.contact,
        if (PassageSignals.hasIdentifier(text)) DocumentQuestions.references,
      ].take(4),
    );
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
