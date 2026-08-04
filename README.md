# DocuAI

**Intelligent Document Scanner & Offline AI Assistant**

An Android document scanner that captures, enhances, reads and answers questions
about your documents — entirely on-device. No account, no server, no analytics,
no network layer at all.

---

## Status

| Phase | Scope | State |
|---|---|---|
| 0 | Foundation: tooling, architecture, theme, routing, storage | ✅ Complete |
| 1 | Domain entities, repository contracts, use cases | ✅ Complete |
| 2 | Hive persistence and the document library | ✅ Complete |
| 3 | ML Kit document scanning | ✅ Complete |
| 4 | On-device OCR (ML Kit Text Recognition) | ✅ Complete |
| 5 | PDF generation and sharing | ⬜ Not started |
| 6 | Full-text search over extracted text | ⬜ Not started |
| 7 | Offline assistant (retrieval; optional on-device LLM) | ⬜ Not started |
| 8 | Polish, accessibility and Play Store release | ⬜ Not started |

Screens whose feature has not been built render a `PhasePlaceholder` naming the
phase that replaces them — `grep -r PhasePlaceholder lib` currently returns
search and the assistant. The table above is the authority on what remains;
placeholders only mark whole screens, not individual actions still to come.

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
| OCR | Google ML Kit Text Recognition |
| Export | `pdf` + `share_plus` |
| Backend | **None** — by design |

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

DocuAI has no network permission, no backend and no telemetry. Scanning, text
recognition, search and the assistant all execute locally. Documents never leave
the device.

---

## Release checklist (Phase 8)

- [ ] Create the release keystore and `android/key.properties` (both git-ignored)
- [ ] Enable R8 with ML Kit keep-rules, then re-test scanning in release mode
- [ ] Adaptive launcher icon and splash screen
- [ ] Accessibility pass (contrast, touch targets, TalkBack)
- [ ] Build the app bundle and publish the privacy policy
