# Architecture

## Layers

```
lib/
  core/          pure Dart — no Flutter, no database
    constants    state codes, GST slabs, units, settings keys
    formatters   money/date formatting, Indian number-to-words, rounding
    validators   GSTIN (with check digit), PAN, IFSC, phone, PIN, HSN
    tax          the GST engine — the only place tax is computed
    theme        one compact desktop theme, light and dark
  data/
    db           schema, PRAGMAs, migrations, first-run seed
    models       plain classes with fromMap/toMap — no codegen
    demo_data    sample catalogue for a new shop
    repos/       one repository per aggregate, all SQL lives here
  state/
    app_state    session, company, preferences, alerts
    billing_state the live bill at the counter
  print/
    invoice_pdf  A5 landscape / A5 portrait / A4 / 80 mm thermal
    report_pdf   generic table report, statement, labels, Z report
    print_service everything that reaches a printer or a PDF file
  ui/            one folder per screen, dialogs beside the screen that opens them
```

Dependencies point strictly downward: `ui → state → repos → db`, and everything
may use `core`. No repository imports Flutter.

## Why these choices

**SQLite over a server.** A paint shop has one till and no IT staff. An
embedded file opens in under 100 ms, survives a power cut through WAL, and is
backed up by copying one file.

**Repositories, not an ORM.** The queries here are reporting queries —
GSTR-1 groupings, ageing buckets, HSN rollups. Hand-written SQL is shorter and
faster than fighting an ORM, and there is no codegen step to keep in sync.

**One transaction per document.** `SalesRepo.save` writes the header, the
lines, the stock ledger, the customer balance and the counter receipt inside a
single `db.transaction`. An interrupted save can never leave a half bill or
stock that does not match the invoice.

**Snapshot, don't join.** Each bill stores the customer's name, GSTIN and
address, and each line stores the item name, HSN and cost price *as they were
at the time of sale*. Renaming an item next year does not rewrite last year's
invoices, and a price revision does not disturb historic margins.

**One tax engine.** `TaxEngine` is the only code that computes GST. The
billing screen, the credit-note dialog, the purchase editor and the PDFs all
call it, so a bill on screen can never disagree with the bill on paper.

## Tax engine rules

1. Tax is computed per line, then summed — never on the bill total.
2. Intra-state (supplier state == place of supply) → CGST + SGST at half the
   slab each. Inter-state → IGST at the full slab.
3. A bill-level discount is allocated across line taxable values *before* tax,
   in proportion to each line, with the remainder pushed onto the last line so
   no paisa is lost. This matches Sec. 15(3)(a).
4. MRP-inclusive pricing back-calculates taxable value as
   `inclusive / (1 + rate/100)`.
5. Round-off is applied once, to the bill total, and shown as its own line.

`test/tax_engine_test.dart` locks all of this down.

## Database schema

| Table | Holds |
|---|---|
| `company` | single-row shop profile |
| `users` | login, salted SHA-256 password, role |
| `settings` | key/value preferences and document counters |
| `parties` | customers and suppliers (`kind`), with running `balance` |
| `products` | item master, `stock`, prices for three tiers |
| `sales_docs` / `sales_items` | invoices, estimates, challans, credit notes |
| `purchase_docs` / `purchase_items` | supplier bills and purchase returns |
| `payments` | receipts and payments, both manual and auto-at-counter |
| `stock_moves` | append-only stock ledger, one row per movement |
| `expenses` | shop running costs |
| `held_bills` | parked bills, stored as JSON |
| `audit_log` | who did what, when |

### Balance sign convention

`parties.balance` is always the outstanding amount **in the party's natural
direction**: for a customer, positive means they owe you; for a supplier,
positive means you owe them. `PaymentRepo.balanceDelta` is the single place
that decides the sign, and `PartyRepo.ledger` mirrors it when computing the
running column. `recalculateBalances()` rebuilds every balance from the
vouchers and is exposed in Settings as a repair tool.

### Document numbering

`SettingsRepo.nextDocNo` reads and increments the counter **inside the caller's
transaction**, so two tills on the same file can never mint the same number.
Numbers are never re-issued: editing a bill keeps its number, and cancelling
leaves the number in the books marked `CANCELLED`, which is what GST requires.

## Adding a migration

Bump `AppDb.schemaVersion` and add a step to `_migrate`:

```dart
if (from < 2) {
  await d.execute('ALTER TABLE products ADD COLUMN supplier_code TEXT DEFAULT \'\'');
}
```

Steps must be idempotent and non-destructive — a shop's only copy of its books
may be running through them.

## Layout rules

Every list screen is checked at 886 px — the width a page gets inside the
1100 px minimum window, once the sidebar takes its 214 px. Three shared
widgets keep it there:

- `Toolbar` — page toolbars flow onto a second line instead of overflowing.
- `StatStrip` — the tinted summary bar above a list wraps the same way.
- `MinWidthScroller` — fixed-column tables (bills, purchases, the billing
  cart) scroll horizontally below a stated minimum rather than clipping.

Two things are deliberately avoided in the theme, because both assert at
runtime rather than at compile time: `TextTheme.apply(fontSizeFactor:)`, which
throws on any Material 3 slot that has no explicit `fontSize` (use
`AppTheme._scaled`), and a global `ScrollbarThemeData.thumbVisibility`, which
throws for any `Scrollbar` without an attached controller.

## Performance notes

- `PRAGMA journal_mode = WAL`, `synchronous = NORMAL`, 4 MB page cache.
- Indexes on every column the UI filters by: party kind/name/phone, product
  sku/barcode/name, document date/party/status, stock moves by product+date.
- Lists use `itemExtent` so scrolling does not measure rows.
- Product search is debounced at 120 ms.
- The dashboard charts are one `CustomPainter`; no charting package is used.

## Extending it

**A new report:** add a query to `ReportRepo`, then a `ReportData` builder in
`reports_page.dart`. CSV export and PDF printing come for free from the shared
table renderer.

**A new document type:** add it to `DocType`, give it a counter in `SKeys`
and `SettingsRepo._counterKeys`, and decide in `SalesDoc.affectsAccounts`
whether it should post to stock and the ledger.

**A new print format:** add it to `PrintFormat`, return a page format from
`InvoicePdf.formatFor`, and branch in `InvoicePdf.build`.
