# DocuAI

**Intelligent Document Scanner & Offline AI Assistant**

An Android document scanner that captures, enhances, reads and answers questions
about your documents — entirely on-device. No account, no server, no analytics,
and no network layer in DocuAI's own code.

---

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: tooling, architecture, theme, routing, storage | ✅ Complete |
| 1 | Domain entities, repository contracts, use cases | ✅ Complete |
| 2 | Hive persistence and the document library | ✅ Complete |
| 3 | ML Kit document scanning | ✅ Complete |
| 4 | On-device OCR (ML Kit Text Recognition) | ✅ Complete |
| 5 | PDF generation and sharing | ✅ Complete |
| 6 | Full-text search over extracted text | ✅ Complete |
| 7 | Offline assistant (retrieval; optional on-device LLM) | ✅ Complete |
| 8 | Play Store release configuration | 🟨 Code complete — see checklist |
| 9 | Conversations, tags, markup editing, phrase search | ✅ Complete |
| 10 | UX redesign, and import from PDF / Word / text files | ✅ Complete |
| 11 | Assistant intents and extraction quality | ✅ Complete |

Feature development is complete. Phase 8's code-side work is done — signing
config, R8 with ML Kit keep rules, backup disabled, launcher icon with a
monochrome layer, privacy policy — and what remains needs a keystore password,
a physical device or the Play Console, so it cannot be finished from the
repository. The [release checklist](#release-checklist) lists exactly what.

Phases 9 to 11 came after the original plan and are worth naming, because they
changed how the app reads rather than what it stores:

- **The library became a workspace.** Creation lives on the Documents screen
  alone rather than in the shell, so it no longer floats over the page you are
  writing; a document is opened as Read / Edit / Share instead of a column of
  navigation rows; search results group by document and open the page the words
  are on.
- **Import gained files.** A PDF is rendered to pages through Android's own
  renderer and read like a scan; Word and text files arrive as text; pictures go
  through the same normaliser photographs do.
- **Assistant actions carry their meaning.** A button sends an `AssistantIntent`
  rather than the English it is labelled with. Sending the sentence is what once
  had "Explain this document" answered by finding a page containing the words
  "this document".

---

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.41 · Dart 3.11 |
| UI | Material 3, seeded colour scheme, light + dark |
| State | Riverpod 3 |
| Navigation | GoRouter 17 (`StatefulShellRoute`) |
| Storage | Hive CE (metadata) + app-sandbox files (images, PDFs) |
| Scanning | Google ML Kit Document Scanner |
| OCR | Google ML Kit Text Recognition (model bundled — no network) |
| Export | PDF (`pdf`) and Word (`archive` + `xml`), shared via `share_plus` |
| Import | Photos (`image_picker`); `.pdf`, `.docx`, `.txt`, `.md` and images (`flutter_file_dialog`), with PDF pages rendered by `printing` |
| Backend | **None** — by design |

`flutter_file_dialog` rather than the more obvious `file_picker`: every
`file_picker` release below 12 pins `win32 ^5.9`, which cannot resolve alongside
`share_plus 13`, and the version pub settles on instead has no Gradle namespace
and fails the Android build outright. `flutter_file_dialog` has no third-party
dependencies at all and is Android/iOS-only, which suits an Android app better
than a picker carrying desktop packages behind it.

---

## Architecture

Feature-first Clean Architecture with a strict inward dependency rule.

```
lib/
├── main.dart               entry point (one line)
├── bootstrap.dart          composition root: error handlers, Hive, DI, runApp
└── src/
    ├── app.dart            MaterialApp.router
    ├── core/               cross-cutting: theme, router, storage, errors, widgets
    └── features/<feature>/
        ├── domain/         entities · repository interfaces · use cases
        ├── data/           Hive models · data sources · repository impls
        └── presentation/   Riverpod providers · screens · widgets
```

**The rule:** `presentation → domain ← data`.

The `domain` layer is pure Dart. It imports no Flutter, no Hive, no ML Kit —
which is what makes use cases unit-testable with no emulator, and what allows
the storage engine to be swapped without touching business logic.

Two deliberate consequences:

- **Entities are separate from models.** `Document` (domain) and
  `DocumentModel` (`@HiveType`, data) are distinct classes with explicit
  mapping. This is the step most tutorials skip.
- **Errors change shape at the boundary.** Data sources throw
  `CacheException` / `MlKitException`; repositories catch them and return a
  sealed `Failure`, so the UI handles errors with an exhaustive `switch` the
  compiler verifies.

### Results, not exceptions

Every repository method and use case returns `FutureResult<T>` —
`Future<Result<T>>`, where `Result` is a sealed `Success` / `Failed` pair. No
repository throws across the domain boundary, so a caller cannot forget an
error path:

```dart
switch (await recognizeDocumentText(id)) {
  case Success(:final value): showText(value.extractedText);
  case Failed(:final failure): showMessage(failure.message);
}
```

`Result` is hand-written rather than taken from `dartz` or `fpdart`: sealed
classes and pattern matching are language features, and a 100-line file with no
functional-programming vocabulary is easier to defend than a dependency.

Which outcomes count as failures is a deliberate part of each contract — a
search that matches nothing, a share sheet the user dismisses and a blank page
that yields no text are all *successes*, because nothing went wrong.

The alias is `FutureResult` rather than the more obvious `AsyncResult` because
Riverpod 3 exports a type of that name; sharing it would force a `hide` clause
on every file that touched both.

The one exception is `watchDocuments()`, which returns a plain
`Stream<List<Document>>`. A stream already has an error channel, and Riverpod
surfaces it as `AsyncValue.error` — wrapping each event in a `Result` as well
would give one failure two paths to travel.

### Storage model

Hive holds **metadata only** — ids, titles, timestamps, tags, extracted text and
page paths. Images and PDFs live on disk under the app documents directory.

Paths are persisted **relative** and resolved through `StoragePaths` at read
time, because Android does not guarantee the absolute sandbox path survives a
reinstall or update.

`DocumentLocalDataSource` is the only class where Hive and the file system meet.
It copies scanned pages in rather than moving them, deletes a half-built folder
if any copy fails, and on delete removes the Hive record *before* the files — a
record pointing at missing images shows a broken thumbnail the user cannot get
rid of, whereas files with no record are invisible and reclaimable later.

Type ids are declared once in `HiveTypeIds` and are append-only. `2` is reserved
and currently unused: tags are plain normalised strings on `Document`, and
renumbering after release would reinterpret every stored record.

### Seeing the library before scanning exists

Scanning arrives in Phase 3, so debug builds carry a **Developer → Add sample
documents** action in Settings that generates a few documents with rendered
page images. It sits behind `kDebugMode`, a compile-time constant, so the tree
shaker removes it and the page renderer from release builds. Phase 8 deletes
the file.

---

## Getting started

```bash
flutter pub get
flutter run
```

Requires the Flutter stable channel and an Android device or emulator.

> **Scanning needs a real device.** ML Kit Document Scanner is a Google Play
> Services module downloaded on demand, so it does not work on emulator images
> without the Play Store, or on non-GMS devices. DocuAI detects this rather
> than failing on tap — see below.

### Scanning

The scanner is a native activity, so `ScanScreen` shows no camera of its own.
It reports whether the module is usable, starts the flow, and handles what
comes back.

`MainActivity` carries one method channel of its own, asking
`GoogleApiAvailability` whether Play Services is present. Without it the only
way to discover a non-GMS device is to launch the scanner and watch it fail,
which puts an error where an explanation belongs.

Three details come from the plugin's Android source rather than its docs, and
`MlKitDocumentScanner` exists to normalise them:

| Plugin behaviour | What the wrapper does |
|---|---|
| Cancelling answers with `result.error(...)`, not an empty result | Translates to an empty page list, matching `ScannerRepository`'s contract |
| Returned paths are `Uri.path` values in the app cache | Left absolute — they belong to the scanner, so `createFromImages` copies rather than moves |
| Scanner instances live in a Kotlin map until `close()` | One instance per scan, always closed in a `finally` |

`ScanScreen` starts on an explicit tap rather than automatically. An
auto-launching screen relaunches the scanner every time the user navigates back
onto it, so backing out of a freshly saved document would reopen the camera.

### Text recognition

Unlike the scanner, the recognition model is **bundled into the APK** rather
than fetched from Play Services, so it works on every device — including the
ones where scanning is unavailable and pages came from the gallery.

Recognition starts automatically the first time a document with unread pages is
opened, which is what makes a freshly scanned document searchable without being
asked to press anything. This cannot loop: a run leaves every page either
`completed` or `failed`, so the document's aggregate status is no longer
`pending` and the trigger is false on every later open. Pages that failed are
retried only on an explicit tap — a page that cannot be read will not read any
better for being reopened.

One unreadable page does not fail the document. Each page records its own
outcome, the run continues, and the text that was recovered is kept and
indexed. That is why `Document.ocrStatus` is derived from the pages rather than
stored alongside them.

The native recogniser is created once and reused across a batch. Constructing a
detector allocates a native model, and a twenty-page document would otherwise
allocate twenty.

#### Rebuilding the page from the hierarchy

DocuAI does **not** use `RecognizedText.text`. That property is Android's
`Text.getText()`, which concatenates *block* texts with newlines — fine for a
page of prose where a block is a paragraph, useless for the documents this app
exists for. ML Kit segments a bill by visual grouping, so a heading word, a
field label and its value each become their own block, and the flat string comes
back as:

```
Electricity
Bill
Amount
5000
```

`RecognizedTextComposer` walks `TextBlock → TextLine → TextElement` and
reassembles the page from the bounding boxes ML Kit already provides: lines are
rebuilt from their elements in reading order, fragments whose vertical extents
overlap are merged into one visual row and ordered left to right, and a vertical
gap wider than 1.4× the median row height becomes a blank line.

```
Electricity Bill
Amount: 5000
```

Two deliberate constraints:

- **Nothing is invented.** Fragments on a row are joined with a single space and
  nothing else — no colons or dashes inserted to make a label look like a label.
  The assistant quotes recognised text *verbatim*, so a fabricated separator
  would end up inside an answer presented as a quotation from the user's own
  document.
- **Left-to-right is assumed**, which holds for `TextRecognitionScript.latin` —
  the only script configured.

This was not only a readability problem. `PassageExtractor` discards candidates
under 12 characters as fragments, so with the flat output a bill's `Electricity`
(11), `Amount` (6) and `5000` (4) were *all* dropped — the assistant could see
almost nothing on exactly the documents it was built for.

### PDF export

Composition runs on a **background isolate**. Rendering decodes and re-encodes
every page image, which for a twenty-page document is seconds of CPU — on the
UI isolate that is a frozen app. The `pdf` package is pure Dart, so moving the
work costs nothing but the hop, and `PdfJob` carries only strings so it can
cross the isolate boundary.

A page whose image cannot be read aborts the export. A PDF quietly missing
page 3 is worse than one that failed loudly, because the user would only find
out after sending it to someone. Missing files are detected before rendering
starts, so the failure costs milliseconds rather than a full render.

The file is named after the document, sanitised — the title is what the share
sheet and the receiving app display, and `document.pdf` tells a recipient
nothing.

Exporting and sharing are one action. Whether a PDF already exists is an
implementation detail, so `ShareDocument` reuses one when it can and composes
one when it cannot; a failed share retries with a fresh render, since a
recorded PDF that Android has since cleared is the likeliest cause.

### Search

Ranking is Okapi BM25. Counting term occurrences gets two things wrong that
BM25 corrects: a word appearing twenty times is not twenty times as relevant
(`k1` saturates it), and a long document is not more relevant merely for having
more words (`b` normalises by length). Titles are weighted 3×, so a document
*called* "Electricity bill" outranks one that mentions electricity in passing.

The index is stored as a **forward** index — one entry per document holding its
term frequencies — not the inverted token-to-postings map a search engine would
use. An inverted index wins when the vocabulary cannot be walked per query;
this is a personal library of tens to low hundreds of documents, so scoring
every entry is a few thousand hash lookups. In exchange, updating one document
is a single write and deleting one is a single delete, where an inverted index
would have to touch every token that document contributed. `SearchRepository`
hides the choice, so postings remain a drop-in replacement.

Entries are plain maps, not `@HiveType` models: the index is derived data, so a
format change needs no migration — only a version bump and a rebuild. The
reconciler runs when the search screen opens and rebuilds if the version is
stale or the entry count disagrees with the library, which self-heals both
documents that predate the index and entries left behind by a failed delete.

Snippet offsets are the fiddly part. Every transformation preserves length —
newlines become spaces one-for-one — and the ellipses are added last with the
highlight offset adjusted for them. A `trim()` or a whitespace collapse would
silently shift the range, producing a highlight over the wrong characters or a
`RangeError` inside a `build`.

### The offline assistant

Retrieval-first, with **no language model**. `flutter_gemma` is not a
dependency. `AnswerSource.onDeviceModel` exists on the entity as the seam for
the optional enhancement; nothing sets it yet.

Answers are **quoted, never composed**. The reply is the highest-scoring passage
from the user's own documents, whitespace-normalised and nothing else. That is
what makes an assistant defensible with no model behind it: there is no step at
which anything could be invented, because every character shown was read off a
page the user scanned.

Retrieval is coarse-to-fine, reusing the Phase 6 index rather than building a
second one:

1. **Documents** — BM25 narrows the library to six candidates in one call.
2. **Passages** — page text is split into sentences, and each is scored against
   the question.

`SearchHit.snippets` cannot serve stage 2: they are display artefacts with a
fixed 60-character radius, capped at three per document.

Passage ranking is a different function from BM25 on purpose. BM25 ranks
documents across a corpus, where the hard problem is rarity. By stage 2 every
candidate already comes from a relevant document, so what matters is which span
most completely contains the question — `coverage × frequency × proximity ×
lengthNorm × intent × documentPrior`, all bounded, all multiplied, so no single
signal can run away with the ranking.

**Stopwords appear here and nowhere else.** BM25 needs none — `idf` discounts
common words statistically. A *coverage ratio* does, because it treats "the" as
worth exactly as much as "deadline": without the list, "when is the deadline"
scores a passage containing only "is" at one third coverage, and a confident
answer gets assembled out of a preposition.

The **intent boost** reflects the corpus. Bills and agreements are
overwhelmingly asked *when* and *how much*, so a question about a date lifts
passages containing one, and likewise for amounts. It reorders candidates and
never invents one. The signal patterns deliberately reject bare integers — a
page number would otherwise register as an amount on every page.

Three outcomes, and the third matters:

| Condition | Answer |
|---|---|
| Passages above the coverage floor | Top passage quoted, with citations |
| Nothing above the floor | "I could not find an answer to that" |
| **No document has recognised text** | Says *that*, specifically |

"Not found" would send a user whose documents were never OCR'd looking for a
phrasing problem they do not have.

**History is deliberately not used as retrieval context.** Each question is
answered independently. Resolving "what about the other one?" needs coreference,
which a lexical retriever cannot do — feeding it prior turns would silently
corrupt the query terms and produce confidently wrong retrieval. This is the
clearest place the optional on-device model would earn its place.

> The exported PDF is images only, not searchable. A searchable text layer
> needs per-block bounding boxes to position invisible text, and
> `OcrRepository` currently returns plain text — ML Kit provides the geometry,
> DocuAI discards it. Worth revisiting if the OCR schema ever grows.

### Quality gates

```bash
flutter analyze   # must be clean
flutter test      # widget + unit tests, no emulator required
```

Entities are generated with Freezed. After changing one, or on a fresh clone if
the generated files look stale:

```bash
dart run build_runner build
```

Domain use cases are tested against hand-written fakes in `test/helpers/` — the
domain layer has no dependencies, and its tests do not add one.

---

## Privacy

DocuAI has no backend, no account system and no analytics of its own. Scanning,
text recognition, search and the assistant all execute locally, and documents
never leave the device.

**Backup is disabled explicitly.** `allowBackup` defaults to `true`, which would
have let Android Auto Backup copy the Hive database — document metadata *and*
the full recognised text of every scan — to the user's Google Drive. Both the
cloud-backup and device-transfer paths are opted out of.

**One honest caveat.** The release build holds `INTERNET` and
`ACCESS_NETWORK_STATE`, so they appear on the Play listing. Neither is requested
by DocuAI: they arrive with `com.google.android.datatransport`, the
usage-telemetry component inside Google's ML Kit libraries. DocuAI's own code
has no HTTP client and makes no requests. The permissions can be stripped with
`tools:node="remove"`, but that has to be verified with a real scan in a release
build first — see [PRIVACY.md](PRIVACY.md).

---

## Release checklist

Done:

- [x] Real application ID (`com.sidrahayat.docuai`), minSdk 24, targetSdk 36
- [x] R8 and resource shrinking enabled, with narrow ML Kit keep rules
- [x] Auto Backup disabled (cloud backup **and** device transfer)
- [x] Adaptive launcher icon, generated by `flutter_launcher_icons` from
      `assets/icons/`, with a monochrome layer for Android 13+ themed icons
- [x] Splash pinned to the brand ink in both light and dark, so the first frame
      is DocuAI rather than the platform default
- [x] Route logging gated behind `kDebugMode`, and error logging silenced in
      release — an exception string here routinely carries a document title
- [x] Import scratch files cleared on each import rather than left in the cache
- [x] Privacy policy written ([PRIVACY.md](PRIVACY.md)), and honest about the
      ML Kit telemetry permissions
- [x] `flutter build appbundle --release` succeeds

Yours to complete — these need a keystore password, a physical device or the
Play Console, and cannot be done from the repository:

- [ ] **Create the upload keystore** and `android/key.properties` — see
      [`android/key.properties.example`](android/key.properties.example). Until
      this exists the release build signs with the **debug** key and Play will
      reject it. The Gradle build prints a warning saying so.
- [ ] **Re-test on a device in release mode**, with R8 active: scan a document,
      confirm text recognition, import a large PDF, share a PDF and a Word file.
      R8 is the change most likely to break something host tests cannot see.
- [ ] Host the privacy policy and put its URL in the Play Console listing
- [ ] Accessibility pass — TalkBack, and the system font at maximum. Text
      scaling is currently clamped to 1.4× in `app.dart`; raising it needs a
      device to check what the clamp was protecting.
- [ ] Show the app version in Settings (needs a decision on `package_info_plus`
      versus a generated constant) and link the hosted policy from there
- [ ] Play Console: store listing, screenshots, content rating, Data safety form
