# Van Cortlandt Bench Adoption Registry

A single-page app that serves as the one source of truth for Van Cortlandt Park's bench adoption program.

**Live:** https://lindsaymiao2021.github.io/bench-registry/

## What it does
- **Browse:** all 520 benches, grouped by park area. Each bench is a square coloured by its status (available, adopted, ending within 90 days, or reserved). There's also a searchable list view.
- **Map:** every bench plotted on an OpenStreetMap map of the park, coloured by status. The status filters and search dim the benches that don't match, and clicking a bench opens its details. Positions are approximate, generated within each area or along each trail.
- **Look up a bench:** see who adopted it (or "Anonymous donor"), the dates and length of the term, the plaque inscription, any future reservations, and past adoptions.
- **Accounts:** you must create an account (name, email, password) or sign in before you can reserve a bench.
- **Reserve any length of time:** pick a first day and a last day from calendar date pickers. Quick buttons fill in 1 week, 1 month, 6 months, 1 year or 5 years. The calendar won't let the last day run into the next booking.
- **Cancel at any time:** under "My adoptions", or from the bench itself. Cancelling a reservation that hasn't started removes it. Cancelling one that's running ends it yesterday, so the bench is open to others right away. Past terms show as "(cancelled)" in the bench history.

## Design decisions and assumptions
- **Status is derived, never stored.** The only data is a list of adoption records `{benchId, userId, donor, start, end, …}`. A bench's status comes from comparing those dates with today's date, so nothing goes stale.
- **One rule prevents double-booking:** two terms on the same bench can't overlap. The date pickers are limited to the next free window, and the rule is checked again when you submit. Bookings can fill gaps between other bookings.
- **Terms include both dates:** a term from Sep 22 to Sep 28 is 7 days.
- **Only your own adoptions can be cancelled.** Each record stores the id of the account that made it, and the cancel control only appears for your own records. The sample donors have no account.
- **Privacy:** the account email is never shown publicly. Donors can choose to be listed as anonymous, and the name shown on the registry can differ from the account name.
- **Plaque limit:** 3 lines of 32 characters each, engraved in capitals (an assumption).
- **Bench IDs** follow the pattern `VC-<AREA>-<NNN>`. The inventory and donors are sample data.
- **No payment**, as the brief specifies.

## Limitations: this is a front-end demo
- **Data is stored per browser.** Accounts and adoptions are saved in `localStorage`, so they aren't shared between visitors or devices.
- **Passwords are salted and hashed (SHA-256)** before they're stored, but authentication runs in the browser, so it isn't real security.
- **For production**, the same data model would move behind a small API with:
  - server-side sessions, and password hashing with bcrypt or argon2;
  - a database, for example Postgres with an exclusion constraint on (bench, date range), so the database itself enforces the no-overlap rule;
  - cancellation checked on the server against the signed-in user.
- **Next steps:** staff tools (edit or cancel any adoption, CSV export), renewal reminder emails, and real GPS coordinates for each bench in place of the approximate positions.
