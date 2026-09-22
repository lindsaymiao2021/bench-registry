# Van Cortlandt Bench Adoption Registry

A single-page app that serves as the one source of truth for Van Cortlandt Park's bench adoption program.

## What it does
- **Browse:** all 520 benches, grouped by park area. Each bench is a square coloured by its status (available, adopted, ending within 90 days, or reserved). There's also a searchable list view.
- **Look up a bench:** see who adopted it (or "Anonymous donor"), the term, the start and end dates, the time remaining, the plaque inscription, any future reservation, and past adoptions.
- **Adopt a bench:** enter your name, email, start date, term (6 months to 10 years), a plaque inscription, and whether to appear as anonymous. If a bench is already taken, the form lets you reserve the next term instead.

## Design decisions and assumptions
- **Status is derived, never stored.** The only data is a list of adoption records `{benchId, donor, email, start, months, end, …}`. A bench's status comes from comparing those dates with today's date. Terms can't go stale, and the full history is kept.
- **One rule prevents double-booking:** two terms on the same bench can't overlap. The earliest allowed start date is today, or the day after the last booked term ends.
- **Terms are inclusive:** a 12-month term starting Sep 22, 2026 ends Sep 21, 2027. Month arithmetic clamps to the end of the month, so Jan 31 plus 1 month gives Feb 28.
- **Privacy:** donor emails are collected for renewals but never shown. Donors can choose to be listed as anonymous.
- **Plaque limit:** 3 lines of 32 characters each, engraved in capitals. This matches a typical small bench plaque (an assumption).
- **Bench IDs** follow the pattern `VC-<AREA>-<NNN>`. The inventory and donors are sample data; the real inventory would be imported from Parks.
- **No payment**, as the brief specifies.

## Limitations and next steps
- **Storage is per browser.** Adoptions are saved in `localStorage`, so this demo isn't yet shared between users. For production I'd put the same data model behind a small API and database, for example Postgres or SQLite with a unique/exclusion constraint on (bench, date range), so the database itself enforces the no-overlap rule.
- **Staff tools:** cancelling or editing an adoption, CSV export, and renewal reminder emails for terms ending within 90 days.
- **A real map:** bench GPS coordinates on a park map instead of the per-area grid.
