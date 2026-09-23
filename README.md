# Van Cortlandt Bench Adoption Registry

A single-page app that serves as the one source of truth for Van Cortlandt Park's bench adoption program.

**Live:** https://lindsaymiao2021.github.io/bench-registry/

## What it does
- **Browse:** all 520 benches, grouped by park area. Each bench is a square coloured by its status (available, adopted, ending within 90 days, or reserved). There's also a searchable list view.
- **Map:** every bench plotted on an OpenStreetMap map of the park, coloured by status. The status filters and search dim the benches that don't match, and clicking a bench opens its details. Positions are approximate, generated within each area or along each trail.
- **Look up a bench:** see who adopted it (or "Anonymous donor"), the dates and length of the term, the plaque inscription, any future reservations, and past adoptions.
- **Accounts:** you must create an account or sign in before you can reserve a bench. Creating an account is its own flow (full name, email, password and a password confirmation), and it ends on an "Account created" confirmation, so you can always tell sign-up apart from sign-in.
- **Reserve for later:** if other people are booked ahead of you, the panel says "Not available right now", names who has the bench, says how many more are lined up and what number in line you'd be, and the button turns amber: "Reserve for later · #3 in line, starts {date}". Reserving a free bench for a future date stays an ordinary green "Reserve" button.
- **The line for each bench:** when a bench has upcoming reservations, the panel lists everyone in order (1 has it now, 2 is next, 3 after that), with their dates.
- **Reserve any length of time:** pick a first day and a last day from calendar date pickers. Quick buttons fill in 1 week, 1 month, 6 months, 1 year or 5 years. The calendar won't let the last day run into the next booking.
- **Cancel at any time:** under "My adoptions", or from the bench itself. Cancelling a reservation that hasn't started removes it. Cancelling one that's running ends it yesterday, so the bench is open to others right away. Past terms show as "(cancelled)" in the bench history.

## Design decisions and assumptions
- **Status is derived, never stored.** The only data is a list of adoption records `{benchId, userId, donor, start, end, …}`. A bench's status comes from comparing those dates with today's date, so nothing goes stale.
- **One rule prevents double-booking:** two terms on the same bench can't overlap. The date pickers are limited to the next free window, and the rule is checked again when you submit. Bookings can fill gaps between other bookings.
- **Terms include both dates:** a term from Sep 22 to Sep 28 is 7 days.
- **Only your own adoptions can be cancelled.** Each record stores the id of the account that made it, and the cancel control only appears for your own records. The sample donors have no account.
- **Privacy:** the account email is never shown publicly. Donors can choose to be listed as anonymous, and the name shown on the registry can differ from the account name.
- **Plaque limit:** 3 lines of 32 characters each, engraved in capitals (an assumption).
- **Bench names** are plain and readable, like "Parade Ground Bench 12" (the area plus a number). Behind the scenes each bench also keeps a stable internal ID, so renaming a bench never breaks its adoption history. The inventory and donors are sample data.
- **No payment**, as the brief specifies.

## Architecture: one shared registry
- **Front end:** a single static page (`index.html`, hosted on GitHub Pages) with no build step. It uses Leaflet and OpenStreetMap for the map.
- **Back end:** [Supabase](https://supabase.com), which provides Postgres, authentication and realtime updates. Every visitor sees the same adoptions, and a new adoption shows up on everyone's open page within a second or two.
- **Accounts:** handled by Supabase Auth. Passwords are hashed server-side and never touch the page's storage, and sessions persist across visits.
- **The database enforces the rules, not just the page** (see [`supabase-setup.sql`](supabase-setup.sql)):
  - an exclusion constraint on `(bench_id, daterange(start, end))` makes double-booking impossible, even if two people reserve at the same instant;
  - row-level security lets anyone read the registry, but only signed-in people can reserve, only in their own name, and not in the past;
  - there are no update or delete permissions; the only change allowed is `cancel_adoption()`, which checks that the adoption belongs to the caller;
  - emails live only in Supabase Auth, never in the public `adoptions` table.
- **Why this key is public:** the Supabase URL and *publishable* key in `index.html` are meant to be in client code. Access is controlled by the row-level-security policies, not by keeping the key secret.
- **Offline fallback:** if Supabase can't be reached (or the config is empty), the page falls back to a browser-only demo using `localStorage`.

### Setting it up yourself
1. Create a Supabase project, and under **Authentication → Sign In / Providers → Email**, turn off "Confirm email" (optional, but it keeps sign-up instant for a demo).
2. Open **SQL Editor**, paste in `supabase-setup.sql`, and click **Run**. This creates the table, the rules and the sample data.
3. Put your project URL and publishable key into `SUPABASE_URL` and `SUPABASE_KEY` near the top of the script in `index.html`.

## Next steps
- Staff tools: edit or cancel any adoption, CSV export, and renewal reminder emails for terms ending within 90 days.
- Real GPS coordinates for each bench, in place of the approximate positions.
