# DocuAI — Privacy Policy

**Last updated: 5 August 2026**

DocuAI is an offline document scanner. This policy describes what the app does
with your information. The short version: it does not collect any, because it
has no way to send any.

---

## What DocuAI collects

**Nothing.** DocuAI has no account system, no analytics, no advertising SDK, no
crash-reporting service and no server of its own.

## What DocuAI stores, and where

Everything DocuAI creates stays in its private application storage on your
device:

| Data | Where it lives |
|---|---|
| Scanned page images (JPEG) | App-private files directory |
| Generated PDFs | App-private files directory |
| Document titles, dates, tags | Local database (Hive) |
| Text recognised from your pages | Local database (Hive) |
| Search index built from that text | Local database (Hive) |
| Assistant questions and answers | Local database (Hive) |
| Theme preference | Local database (Hive) |

Android protects this directory from other applications. Uninstalling DocuAI
deletes all of it.

## Network access

**DocuAI's own code makes no network requests.** It has no HTTP client, no API
endpoints, no analytics SDK and no backend. Your documents are never transmitted
by this app.

DocuAI does, however, hold the `INTERNET` and `ACCESS_NETWORK_STATE`
permissions, and you will see them on its Play Store listing. They are not
requested by DocuAI itself: they are added automatically by Google's ML Kit
libraries, which bundle a usage-telemetry component
(`com.google.android.datatransport`) that reports aggregate ML Kit usage
statistics to Google.

To be exact about what this means:

- **Your documents, page images, recognised text and questions are never
  uploaded.** Nothing in DocuAI reads them and sends them anywhere.
- The telemetry belongs to Google's libraries, is about ML Kit's own operation,
  and is governed by
  [Google's Privacy Policy](https://policies.google.com/privacy).
- Text recognition needs no network at all — the model ships inside the app.
- The document scanner is a Google Play Services module, which the Play Services
  app downloads in its own process the first time you scan.

## Cloud backup

Automatic backup is **disabled**. Android's Auto Backup would otherwise copy an
app's data to your Google Drive; DocuAI opts out explicitly, for both cloud
backup and device-to-device transfer, so your documents are not duplicated off
the device without your knowledge.

To move documents to another device, export and share them yourself.

## On-device processing

Two Google ML Kit components run entirely on your device:

- **Document Scanner** — camera capture, edge detection and perspective
  correction. Delivered as a Google Play Services module. Images are processed
  locally; DocuAI does not upload them.
- **Text Recognition** — reads text from your scans. The model is bundled inside
  the app, so it works with no network connection at all.

The assistant answers questions by quoting text already recognised from your own
documents. There is no language model and no external service involved.

## When you share a document

Sharing is the only way information leaves DocuAI, and it happens only when you
choose it. Tapping **Share as PDF** opens Android's share sheet and hands the
file to the app you pick — email, messaging, cloud storage, whatever you select.
What that app then does with the file is governed by *its* privacy policy, not
this one.

## Permissions

| Permission | Why |
|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | Added by Google's ML Kit libraries for their own telemetry, as described above. DocuAI's code does not use them. |
| *(no runtime permissions)* | DocuAI never asks you to grant anything. Scanning runs inside the Google Play Services scanner activity, which handles camera access itself, so DocuAI holds no camera, storage, location, microphone or contacts permission. |

## Children

DocuAI is not directed at children and collects no information from anyone,
including children.

## Your rights

Because DocuAI holds no data about you on any server, there is nothing to
request, correct or delete from us. You control everything: delete a document
inside the app, or uninstall it to remove all data at once.

## Changes to this policy

If a future version of DocuAI changes what it stores or gains network access,
this policy will be updated before that version is published, and the change
will be visible in the app's permission list on Google Play.

## Contact

Questions about this policy: **muhammadarhumj@gmail.com**
