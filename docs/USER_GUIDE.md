# PaintPro Billing — User Guide

## 1. First run checklist

Sign in with **admin / admin123**, then work through these four screens once.

1. **Settings › Users & security** — change the admin password immediately.
   Add a cashier account for each person who bills.
2. **Settings › Business profile** — shop name, address, **state**, GSTIN,
   phone, and bank details. The state is not optional: it decides whether a
   sale carries CGST+SGST or IGST.
3. **Settings › Billing & tax** — invoice prefix and starting number. If you
   are continuing from a manual book, set the next number to carry on from
   where the book stopped. Use `{FY}` in the prefix (for example `INV/{FY}/`)
   to restart numbering each financial year.
4. **Settings › Printing** — choose **A5 Horizontal**, then set the same size
   in the Windows printer preferences (see section 6).

Then load your stock: **Products › ⋮ › Download CSV template**, fill it in
Excel, and **⋮ › Import from CSV**. Or press **New item** and type them in.
To explore first, use **⋮ › Load sample catalogue**.

---

## 2. Billing at the counter

Press **F2** from anywhere to reach the billing screen. The cursor is already
in the search box.

| Step | What you do |
|---|---|
| Add an item | Scan the barcode, or type part of the name / code / shade and press Enter |
| Add three of something | Type `3*` then the code — e.g. `3*P00012` — and press Enter |
| Fix a quantity | Click the Qty cell on the line and type over it |
| Change a rate | Click the Rate cell (useful for a negotiated price) |
| Give a line discount | Type a percentage in the Disc % cell |
| Give a bill discount | **F6**, then a percentage or a flat amount |
| Add tinting or labour | **F7**, pick a preset or type your own |
| Choose the customer | **F3**, search by name or phone, **Ctrl+N** to add a new one |
| Take payment | **F8** — mode, cash received, change due |
| Finish | **F9** saves and prints. **F10** saves without printing |

**Walk-in sales need no customer.** The bill goes to "Cash / Walk-in Customer"
automatically. Pick a real customer when you need a GSTIN on the bill, are
selling on credit, or want the sale in their ledger.

**Credit sales** require a named customer — the software will stop you from
booking credit against the walk-in account, because that debt could never be
collected from anyone.

**Parking a bill.** A customer walks off to fetch their card; press **F4** to
park the bill and serve the next person. **F5** brings it back.

**Tax-inclusive billing.** If you quote MRP and want the tax worked backwards
out of it, switch on the **Incl. tax** chip on the billing screen, or make it
the default in *Settings › Billing & tax*.

---

## 3. Keyboard shortcuts

| Key | Action |
|---|---|
| `F2` | Speed billing / focus the search box |
| `F3` | Choose or create the customer |
| `F4` | Park the current bill |
| `F5` | Recall a parked bill |
| `F6` | Bill discount |
| `F7` | Add a charge or custom line |
| `F8` | Payment — mode, cash received, change |
| `F9` | Save and print |
| `F10` | Save without printing |
| `F12` | Print preview |
| `Esc` | Clear the bill |
| `Ctrl` + `Del` | Remove the selected line |
| `Alt` + `1`…`9` | Jump between main screens |
| `Ctrl` + `N` | New customer (inside the customer picker) |

---

## 4. Purchases and stock

**Entering a supplier bill** (Purchases › New purchase) does four things at
once: brings the stock in, updates each item's cost price, records the input
tax credit, and adds the amount to what you owe that supplier.

Enter the **MRP** and **Sale** columns on the purchase line whenever the
supplier revises prices — the item master is updated from them, so you never
have to edit prices twice.

**Physical count.** Inventory › the sliders icon on any row. Enter what you
actually counted; the difference is written to the stock ledger with a reason,
so the correction is always traceable.

**Stock ledger.** The clock icon on any row shows every movement of that item —
which bill sold it, which purchase brought it in, who adjusted it and why.

**Reorder levels.** Set "Low-stock alert at" on each item. The count appears in
the title bar and on the dashboard, and Inventory › Low stock lists them.

---

## 5. Money you are owed

- **Customers › the wallet icon** records a receipt. Choose a specific bill to
  settle it, or leave it "on account" to reduce the oldest balance.
- **Customers › the receipt icon** shows the full ledger and prints a
  statement you can hand or email to the customer.
- **Reports › Outstanding & ageing** lists every unpaid bill bucketed by age,
  with phone numbers — this is your call list.
- **Discount allowed** on a receipt writes off a small balance (the rounding
  a customer refuses to pay) without disturbing the original invoice.

---

## 6. Printing

### Setting up A5 horizontal in Windows

1. **Settings › Printers & scanners** → your printer → **Printing preferences**
2. Paper size **A5**, orientation **Landscape**
3. Margins **None** or the printer's minimum
4. For a dot-matrix printer, add a **custom size of 210 × 148 mm**

Then in PaintPro, *Settings › Printing* → **A5 Horizontal**, and switch on
**Send straight to the default printer** so F9 does not stop to ask.

### Formats

| Format | Size | Use it for |
|---|---|---|
| A5 Horizontal | 210 × 148 mm | Everyday counter bills — two per A4 sheet |
| A5 Vertical | 148 × 210 mm | Narrow stationery |
| A4 | 210 × 297 mm | B2B invoices with many lines |
| Thermal 80 mm | roll | Receipt printers |

### Why bills print "Rs." and not "₹"

The PDF uses the standard built-in font so the file stays around 20 KB and
prints instantly on any printer, including old dot-matrix units that would
otherwise choke on an embedded font. That font has no rupee glyph, so amounts
are prefixed `Rs.`. On screen you still see `₹`.

---

## 7. GST

### What the software computes

Tax is worked out **line by line**, never on the bill total, and CGST+SGST or
IGST is chosen from the **place of supply** — the customer's state if they have
one, otherwise your own. A bill discount is spread across the lines *before*
tax, because a discount shown on the face of the invoice reduces the taxable
value under Sec. 15(3)(a).

### Reports for your accountant

| Report | Portal table |
|---|---|
| GSTR-1 · B2B | Table 4 — one row per invoice to a registered buyer |
| GSTR-1 · B2C | Table 7 — consolidated by place of supply and rate |
| GSTR-1 · HSN summary | Table 12 |
| GSTR-3B summary | 3.1(a) outward, 4(A)(5) input tax credit, net payable |

Every report exports to CSV and prints to PDF on your letterhead.

### Before you file

Reconcile the input tax credit figure against **GSTR-2B** on the portal.
PaintPro reports the credit on purchases *you recorded*; the portal allows only
credit your suppliers actually reported. The two differ more often than not.

### Common HSN codes for a paint counter

| HSN | Goods | GST |
|---|---|---|
| 3208 | Paints and varnishes in a non-aqueous medium (enamel, PU) | 18% |
| 3209 | Paints and varnishes in an aqueous medium (emulsion, distemper) | 18% |
| 3210 | Other paints, prepared water pigments | 18% |
| 3214 | Putty, glazier's putty, fillers | 18% |
| 3814 | Thinner, organic composite solvents | 18% |
| 3919 | Self-adhesive tape | 18% |
| 6805 | Emery paper, abrasive powder on a backing | 18% |
| 8205 | Hand tools — putty blades, scrapers | 18% |
| 9603 | Brushes and rollers | 18% |
| 9954 (SAC) | Painting and construction services | 18% |
| 9965 (SAC) | Goods transport / delivery | 18% |

Rates change. Confirm the current rate with your accountant before relying on
this table.

---

## 8. Backups

A backup is written automatically the first time you sign in each day, and the
last 30 copies are kept. You can also back up on demand from
*Settings › Backup & data*.

**Do this once:** in *Settings › Backup & data*, press **Change backup folder**
and point it at a pen drive, an external disk, or a Google Drive / OneDrive
folder that syncs off the machine. A backup sitting on the same hard disk that
fails is not a backup.

**Restoring** replaces everything with the chosen file. Your current data is
kept alongside as a `.pre-restore` file, so a mistaken restore is reversible.
Only an admin can restore, and the app closes afterwards.

---

## 9. Corrections and mistakes

| Situation | What to do |
|---|---|
| Wrong item or quantity, just billed | Open the bill from Invoices and **Cancel bill**, then bill again. Stock and the customer balance are reversed automatically. |
| Customer returns goods | Open the invoice → **Sales return**. Set the return quantity per line, choose cash refund or account credit. A credit note is raised and stock comes back. |
| Wrong price on a past bill | Cancel and re-bill. Invoice numbers are never re-used — a cancelled number stays in the books, which is what GST requires. |
| Balances look wrong | *Settings › Backup & data › Recalculate party balances* rebuilds every balance from the underlying vouchers. |
| Item shows the wrong stock | Inventory → adjust the item to the counted quantity with a reason. |

Cancelling a bill needs Manager or Admin rights. A cashier cannot quietly
remove a sale — every cancellation is written to the audit log with the user
name and time.

---

## 10. Day close

*Reports › Day close (Z report)* shows the day's bills, gross sales, returns,
what was collected by each mode, credit given, expenses paid, and the cash that
should be in the till.

Count the drawer, compare it with **Cash in hand**, print the Z report, and
file it. Any difference is easier to explain today than next week.
