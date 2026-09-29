# English interface and dashboard entry

The PWA uses English labels and an LTR interface. Content language is independent:
existing Persian brand fields, calls to action, captions and rendered slides are preserved.
Catalog responses add English names and descriptions without removing the previous fields.

Signed-in users go straight to their last selected business dashboard. If that business
is no longer available, the app opens the first named business, or the first available
business. Empty accounts see business setup. The header opens a switcher with business
management; account settings remain accessible. Signing out clears the saved selection.

Home, Create, Research, Rivals and Brand use the persistent bottom navigation. Dashboard
counts are calculated from actual posts. The calendar displays Gregorian dates with
English labels while preserving the Saturday-first week and backend weekday keys.

Startup shows only a loading indicator. An English retry message appears if loading fails.
The existing per-build asset URLs and cache invalidation are unchanged.

Validation: Flutter analysis, 13 widget/unit tests, release WASM/web build, 81 backend tests,
and local 390×844 browser screenshots. Preview screenshots use an isolated local database
and fake model output, not production content. No production brands are renamed or deleted.
