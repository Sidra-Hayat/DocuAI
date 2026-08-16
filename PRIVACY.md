# DocuAI — Privacy Policy

The authoritative privacy policy for DocuAI is published at:

**<https://sidra-hayat.github.io/DocuAI/privacy.html>**

That page is the version linked from the Google Play listing, and it is the one
to update when the app's behaviour changes. Its source lives in this repository
at [`docs/privacy.html`](docs/privacy.html).

This file used to hold a second, independent copy of the full policy. It no
longer does: two copies of a legal document drift apart, and the one nobody
remembers to edit is the one that ends up being wrong.

---

## The short version

DocuAI is an offline document scanner. It does not collect, transmit or share
your documents. Pages, recognised text, tags, searches and Assistant
conversations all stay in the app's private storage on your device.

There are no accounts, no advertising, and no analytics or crash reporting of
our own. Automatic backup is switched off for both cloud backup and
device-to-device transfer, which also means **documents are lost if the app is
uninstalled or the device is reset** — export anything you need to keep.

Google's ML Kit and Play Services libraries provide the document scanner and the
on-device text recognition. They include Google's own diagnostics component,
which is why the app carries the `INTERNET` permission it never uses itself.
Your documents are not part of that. See section 6 of the published policy.

## For maintainers

If a change to the app alters what it stores, what it sends, or which
permissions it declares, update `docs/privacy.html` **before** that version is
published — including its effective date — and re-check the Data Safety answers
in the Play Console.
