# PaintPro Billing

GST billing, stock and accounts software for **Indian paint retailers**, built
in Flutter for **Windows 10/11 and macOS**. It runs entirely offline against a
single embedded SQLite file — no server, no subscription, no internet.

The counter screen is built around **speed billing**: scan or type, press
Enter, press F9, and an **A5 horizontal invoice** is on the printer.

---

## Quick start

You need Flutter 3.35 or newer (`flutter --version`). Verified on 3.47.2.

**Windows**

```bat
setup.bat
flutter run -d windows
```

**macOS / Linux**

```bash
./setup.sh
flutter run -d macos
```

The setup script generates the platform runner folders for *your* Flutter
version and then restores this project's source, so the build always matches
your toolchain. Run it once.

Sign in with **admin / admin123** and change the password in
*Settings › Users & security*.

To try the software immediately, open **Products › ⋮ › Load sample catalogue** —
it adds about 35 typical paint, primer, putty and accessory items with stock.

### Release builds

```bash
flutter build windows --release     # build\windows\x64\runner\Release\
flutter build macos --release       # build/macos/Build/Products/Release/
```

The Windows release folder is self-contained: copy it to the shop's PC, create
a desktop shortcut to `paint_billing.exe`, and it runs. No installer needed.

---

## What it does

**Billing**
- Speed billing screen driven entirely by the keyboard (F2–F12)
- Barcode scanner support; `3*CODE` adds three units in one keystroke
- Tax invoice, estimate/quotation, delivery challan, credit note (sales return)
- Park and recall bills (F4 / F5) when a customer steps away
- Line and bill-level discounts, free quantity, tinting and labour charges
- Cash / UPI / card / bank / cheque / credit, with change-due calculation
- Retail, dealer and contractor price lists per customer

**Printing**
- **A5 horizontal (210 × 148 mm)** — the default, two bills per A4 sheet
- A5 vertical, A4, and 80 mm thermal roll
- Original / Duplicate / Triplicate copies, rate-wise tax summary,
  amount in words, bank and UPI details, terms and signature block
- Print preview, save as PDF, and printer discovery from Settings

**GST**
- Line-by-line tax, CGST+SGST or IGST chosen from the place of supply
- MRP-inclusive billing (tax worked backwards out of the price)
- Bill discounts spread across lines *before* tax, per Sec. 15(3)(a)
- GSTIN validation including the mod-36 check digit
- GSTR-1 Table 4 (B2B), Table 7 (B2C), Table 12 (HSN) and a GSTR-3B summary
- Sales and purchase registers, exportable to CSV or PDF

**Stock**
- Paint-aware item master: brand, base, shade code, shade name, pack size
- Full stock ledger — every movement traced to the document that caused it
- Purchase (GRN) entry that updates stock and cost prices in one step
- Low-stock alerts, dead-stock report, stock valuation, physical-count
  adjustment, barcode/shelf label printing
- CSV import and export with a downloadable template

**Money**
- Customer and supplier ledgers with running balance and printable statements
- Receipts, payments, discounts allowed, bill-wise settlement
- Receivables ageing (0–15 / 16–30 / 31–60 / 61–90 / 90+ days)
- Expense book, gross and net profit, day-close (Z) report

**Housekeeping**
- Users with Admin / Manager / Cashier roles and an audit log
- Automatic daily backup, manual backup, and verified restore
- Light and dark themes, six accent colours

---

## Built for modest hardware

The shop PC is usually the slowest machine in the building, so:

- **SQLite in WAL mode** with a 4 MB page cache — the whole application
  footprint is typically under 200 MB of RAM.
- **No charting library.** The dashboard graphs are a single `CustomPainter`.
- **Flat surfaces, no blur, no shadows above 2 dp** — cheap to rasterise on
  Intel HD integrated graphics.
- **Fixed-extent lists** (`itemExtent`) everywhere, so a 10 000-row register
  scrolls without measuring rows.
- **Debounced search** at 120 ms with indexed `LIKE` queries.
- Minimum window 1100 × 680, designed for a 1366 × 768 laptop screen.

---

## Where your data lives

| | |
|---|---|
| Windows | `C:\Users\<you>\AppData\Roaming\com.paintpro\paint_billing\data\paintpro.db` |
| macOS | `~/Library/Containers/com.paintpro.paintBilling/Data/Library/Application Support/com.paintpro.paintBilling/data/paintpro.db` |

The macOS path sits inside the app sandbox container, which is why it is so
long. Windows is not sandboxed, so the path there is the plain AppData one.

Backups go to a `backups` folder beside it, or to any folder you choose in
*Settings › Backup & data*. The exact paths are shown on that screen.

**Keep an off-machine copy.** A daily copy to a pen drive or a synced cloud
folder is the difference between a bad morning and a lost year.

---

## Documentation

- [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) — day-to-day operation, first-run
  checklist, keyboard shortcuts, printer setup, GST filing notes
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — code layout, database
  schema, tax engine, and how to extend it

## Tests

```bash
flutter test
```

50 tests, in three files:

- `tax_engine_test.dart` — intra/inter-state splits, inclusive pricing,
  discount allocation to the paisa, round-off, HSN and rate-wise summaries,
  Indian number-to-words, GSTIN checksum validation.
- `billing_flow_test.dart` — end-to-end against a real SQLite file: a bill
  moves stock, the customer balance and the receipt book together; cancelling
  and editing reverse all three exactly once; bill numbers never repeat;
  credit notes return stock; purchases update cost prices; the negative-stock
  guard holds; GSTR-1 B2B/B2C/HSN, GSTR-3B and the day book report correctly.
- `app_smoke_test.dart` — builds every theme on every desktop platform, and
  mounts all twelve screens at both 1440x900 and the 886 px a page gets at the
  minimum window. Framework assertions and layout overflows only fire when a
  widget is actually built, so this is what keeps them off the counter.

---

## Honest limits

- It does **not** file returns. It prepares GSTR-1 and GSTR-3B figures from
  your books; filing happens on the GST portal.
- It does **not** connect to the e-invoice (IRP) or e-way bill portals.
- Amounts print as `Rs.` rather than `₹`, so bills render identically on every
  printer including old dot-matrix units. The screen shows the real symbol.
- Reconcile input tax credit against GSTR-2B before filing. This software
  reports what you recorded, not what your suppliers filed.
