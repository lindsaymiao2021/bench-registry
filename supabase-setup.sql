-- Van Cortlandt Bench Registry: database setup for Supabase.
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste -> Run.

create extension if not exists btree_gist;

-- One row per adoption term. A bench's status (available / adopted / reserved)
-- is derived from these dates, never stored.
create table if not exists public.adoptions (
  id           uuid primary key default gen_random_uuid(),
  bench_id     text not null check (bench_id ~ '^VC-[A-Z]{2}-[0-9]{3}$'),
  user_id      uuid references auth.users (id) on delete set null default auth.uid(),
  donor        text not null check (char_length(donor) between 1 and 80),
  anonymous    boolean not null default false,
  plaque       text not null default '' check (char_length(plaque) <= 110),
  start_date   date not null,
  end_date     date not null,
  cancelled_at date,
  voided       boolean not null default false,   -- a cancelled reservation that never started
  created_at   timestamptz not null default now(),
  constraint end_after_start check (end_date >= start_date),
  -- The database itself refuses double-bookings: two live terms on the same
  -- bench can never have overlapping date ranges, even if two people click at once.
  constraint no_double_booking exclude using gist (
    bench_id with =,
    daterange(start_date, end_date, '[]') with &&
  ) where (not voided)
);

alter table public.adoptions enable row level security;

-- The registry is public: anyone can see who adopted what (no emails are stored here).
drop policy if exists "anyone can view the registry" on public.adoptions;
create policy "anyone can view the registry" on public.adoptions
  for select using (true);

-- Signed-in people can reserve, only in their own name, and not in the past.
drop policy if exists "signed-in people reserve for themselves" on public.adoptions;
create policy "signed-in people reserve for themselves" on public.adoptions
  for insert to authenticated
  with check (user_id = auth.uid() and start_date >= current_date - 1
              and not voided and cancelled_at is null);

-- No update/delete policies: the only change allowed is cancelling your own term.
create or replace function public.cancel_adoption(aid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare a public.adoptions;
begin
  select * into a from public.adoptions where id = aid for update;
  if not found or a.user_id is distinct from auth.uid() then
    raise exception 'You can only cancel your own adoptions.';
  end if;
  if a.voided or a.end_date < current_date then
    raise exception 'This adoption has already ended.';
  end if;
  if a.start_date >= current_date then
    -- hasn't started yet: remove it from the line entirely
    update public.adoptions set voided = true, cancelled_at = current_date where id = aid;
  else
    -- already running: end it yesterday so the bench is open today
    update public.adoptions set end_date = current_date - 1, cancelled_at = current_date where id = aid;
  end if;
end $$;
revoke all on function public.cancel_adoption(uuid) from public, anon;
grant execute on function public.cancel_adoption(uuid) to authenticated;

-- Push changes to open pages so everyone sees new adoptions live.
do $$ begin
  alter publication supabase_realtime add table public.adoptions;
exception when duplicate_object then null; end $$;

-- Sample data: past, current and upcoming terms by fictional donors (no accounts).
insert into public.adoptions (bench_id, donor, anonymous, plaque, start_date, end_date) values
('VC-PG-001', 'Kingsbridge Garden Society', false, 'REST A WHILE.
— KINGSBRIDGE GARDEN SOCIETY', '2026-05-08', '2027-05-07'),
('VC-PG-005', 'Bronx Birders', false, 'FOR BRONX BIRDERS
WHO WALKED HERE EVERY MORNING', '2017-11-04', '2027-11-03'),
('VC-PG-008', 'Kingsbridge Garden Society', false, 'DONATED BY
KINGSBRIDGE GARDEN SOCIETY', '2022-07-04', '2027-07-03'),
('VC-PG-010', 'Tom O''Brien', false, 'FOR HANNAH RIVERA
WHO WALKED HERE EVERY MORNING', '2023-10-06', '2028-10-05'),
('VC-PG-010', 'Kevin Adeyemi', false, '', '2021-10-06', '2023-10-05'),
('VC-PG-011', 'Samuel Rivera', false, 'REST A WHILE.
— VICTOR O''BRIEN', '2026-08-06', '2027-08-05'),
('VC-PG-012', 'James Okafor', false, 'DONATED BY
JAMES OKAFOR', '2024-08-20', '2027-08-19'),
('VC-PG-014', 'Aisha Patel', false, 'IN LOVING MEMORY OF
PRIYA MORALES', '2023-10-07', '2026-10-06'),
('VC-PG-016', 'Rosa Feldman', false, 'FOR DANIEL KIM
WHO WALKED HERE EVERY MORNING', '2022-03-01', '2027-02-28'),
('VC-PG-016', 'Grace Rivera', false, '', '2020-03-01', '2022-02-28'),
('VC-PG-017', 'Luis Patel', false, 'IN LOVING MEMORY OF
LUIS PATEL', '2026-01-12', '2029-01-11'),
('VC-PG-019', 'Yolanda Patel', false, 'DONATED BY
YOLANDA PATEL', '2016-12-09', '2026-12-08'),
('VC-PG-019', 'Kevin Feldman', false, '', '2014-12-09', '2016-12-08'),
('VC-PG-020', 'Kingsbridge Garden Society', false, '', '2026-10-16', '2027-10-15'),
('VC-PG-021', 'Grace Feldman', false, 'DONATED BY
GRACE FELDMAN', '2026-01-02', '2027-01-01'),
('VC-PG-022', 'Class of 1998, DeWitt Clinton HS', false, '', '2027-02-06', '2028-02-05'),
('VC-PG-024', 'Samuel Okafor', false, 'DONATED BY
SAMUEL OKAFOR', '2026-08-10', '2031-08-09'),
('VC-PG-024', 'Priya Nguyen', false, '', '2024-08-10', '2026-08-09'),
('VC-PG-025', 'Friends of Van Cortlandt Park', false, 'DONATED BY
PRIYA SANTOS', '2026-03-02', '2027-03-01'),
('VC-PG-032', 'Friends of Van Cortlandt Park', false, 'REST A WHILE.
— TOM GOLDBERG', '2026-07-22', '2027-01-21'),
('VC-PG-033', 'Yolanda Goldberg', false, 'REST A WHILE.
— HANNAH SANTOS', '2025-11-27', '2028-11-26'),
('VC-PG-035', 'Maria Goldberg', false, 'IN LOVING MEMORY OF
VICTOR MORALES', '2026-05-04', '2027-05-03'),
('VC-PG-036', 'Omar Santos', false, 'REST A WHILE.
— OMAR SANTOS', '2026-02-18', '2031-02-17'),
('VC-PG-036', 'Grace Santos', false, '', '2024-02-18', '2026-02-17'),
('VC-PG-043', 'Samuel Okafor', false, 'IN LOVING MEMORY OF
AISHA GOLDBERG', '2026-04-21', '2027-04-20'),
('VC-PG-043', 'Omar Santos', false, '', '2024-04-21', '2026-04-20'),
('VC-PG-045', 'Bronx Birders', false, 'FOR SAMUEL RIVERA
WHO WALKED HERE EVERY MORNING', '2026-04-12', '2027-04-11'),
('VC-PG-046', 'Aisha Kim', true, 'REST A WHILE.
— HANNAH FELDMAN', '2025-10-21', '2026-10-20'),
('VC-PG-046', 'Class of 1998, DeWitt Clinton HS', false, 'DONATED BY
RIVERDALE RUNNING CLUB', '2026-10-21', '2027-10-20'),
('VC-PG-047', 'Omar Morales', false, 'IN LOVING MEMORY OF
AISHA OKAFOR', '2026-04-26', '2026-10-25'),
('VC-PG-051', 'Kingsbridge Garden Society', false, 'DONATED BY
DANIEL RIVERA', '2023-10-01', '2026-09-30'),
('VC-PG-054', 'Friends of Van Cortlandt Park', false, '', '2026-11-22', '2027-11-21'),
('VC-PG-057', 'Class of 1998, DeWitt Clinton HS', false, 'IN LOVING MEMORY OF
HANNAH FELDMAN', '2020-04-17', '2030-04-16'),
('VC-PG-058', 'Maria Delgado', false, 'FOR MARIA DELGADO
WHO WALKED HERE EVERY MORNING', '2024-12-13', '2029-12-12'),
('VC-PG-060', 'Daniel Feldman', false, 'DONATED BY
DANIEL FELDMAN', '2025-09-25', '2026-09-24'),
('VC-PG-060', 'Priya Adeyemi', false, '', '2023-09-25', '2025-09-24'),
('VC-PG-061', 'Rosa Santos', false, 'DONATED BY
ROSA SANTOS', '2026-08-08', '2027-08-07'),
('VC-PG-061', 'Hannah Rivera', false, '', '2024-08-08', '2026-08-07'),
('VC-PG-065', 'Aisha O''Brien', false, 'DONATED BY
AISHA O''BRIEN', '2026-05-11', '2026-11-10'),
('VC-PG-065', 'Maria Patel', false, '', '2024-05-11', '2026-05-10'),
('VC-PG-067', 'Victor Kim', false, 'FOR VICTOR KIM
WHO WALKED HERE EVERY MORNING', '2025-08-31', '2030-08-30'),
('VC-PG-069', 'Riverdale Running Club', false, 'REST A WHILE.
— TOM ADEYEMI', '2021-07-01', '2031-06-30'),
('VC-PG-070', 'Rosa Santos', false, 'IN LOVING MEMORY OF
ROSA SANTOS', '2026-02-16', '2027-02-15'),
('VC-LK-001', 'Maria Kim', false, 'DONATED BY
AISHA DELGADO', '2024-07-25', '2029-07-24'),
('VC-LK-001', 'Omar Delgado', false, '', '2022-07-25', '2024-07-24'),
('VC-LK-005', 'Aisha Patel', false, 'DONATED BY
AISHA PATEL', '2024-08-31', '2027-08-30'),
('VC-LK-006', 'Omar Adeyemi', false, 'REST A WHILE.
— OMAR ADEYEMI', '2024-12-06', '2027-12-05'),
('VC-LK-008', 'Aisha Adeyemi', false, 'REST A WHILE.
— PRIYA RIVERA', '2026-01-15', '2028-01-14'),
('VC-LK-010', 'Aisha Okafor', false, 'DONATED BY
AISHA MORALES', '2023-09-30', '2026-09-29'),
('VC-LK-013', 'Beatriz Delgado', false, 'REST A WHILE.
— LUIS O''BRIEN', '2026-05-22', '2029-05-21'),
('VC-LK-015', 'Class of 1998, DeWitt Clinton HS', false, 'FOR CLASS OF 1998, DEWITT CLINTON HS
WHO WALKED HERE EVERY MORNING', '2025-10-28', '2027-10-27'),
('VC-LK-016', 'Yolanda Nguyen', false, 'FOR PRIYA PATEL
WHO WALKED HERE EVERY MORNING', '2017-01-14', '2027-01-13'),
('VC-LK-019', 'Omar Feldman', false, 'REST A WHILE.
— OMAR FELDMAN', '2024-06-12', '2029-06-11'),
('VC-LK-024', 'Rosa Okafor', false, 'DONATED BY
ROSA OKAFOR', '2025-03-03', '2035-03-02'),
('VC-LK-024', 'Kevin O''Brien', false, '', '2023-03-03', '2025-03-02'),
('VC-LK-031', 'Kevin Morales', false, 'REST A WHILE.
— KEVIN MORALES', '2026-01-15', '2028-01-14'),
('VC-LK-031', 'Riverdale Running Club', false, 'DONATED BY
CLASS OF 1998, DEWITT CLINTON HS', '2028-01-15', '2029-01-14'),
('VC-LK-031', 'Kevin Delgado', false, '', '2029-01-15', '2029-07-14'),
('VC-LK-032', 'Daniel Adeyemi', false, 'REST A WHILE.
— LUIS SANTOS', '2026-02-11', '2028-02-10'),
('VC-LK-035', 'Kevin Patel', false, 'FOR AISHA RIVERA
WHO WALKED HERE EVERY MORNING', '2026-03-21', '2027-03-20'),
('VC-LK-038', 'Yolanda Adeyemi', false, 'IN LOVING MEMORY OF
LUIS KIM', '2021-12-03', '2026-12-02'),
('VC-LK-042', 'Maria Adeyemi', false, 'IN LOVING MEMORY OF
TOM MORALES', '2026-02-23', '2027-02-22'),
('VC-LK-042', 'Priya Santos', false, '', '2024-02-23', '2026-02-22'),
('VC-LK-043', 'Riverdale Running Club', false, '', '2026-12-17', '2027-12-16'),
('VC-LK-045', 'Luis Okafor', false, 'FOR SAMUEL PATEL
WHO WALKED HERE EVERY MORNING', '2017-07-07', '2027-07-06'),
('VC-LK-046', 'Aisha Morales', true, 'DONATED BY
ROSA NGUYEN', '2026-04-23', '2026-10-22'),
('VC-LK-048', 'James Morales', false, 'IN LOVING MEMORY OF
AISHA O''BRIEN', '2026-04-13', '2027-04-12'),
('VC-LK-052', 'Daniel Santos', false, 'FOR DANIEL ADEYEMI
WHO WALKED HERE EVERY MORNING', '2026-08-13', '2027-08-12'),
('VC-LK-052', 'Victor Santos', false, '', '2024-08-13', '2026-08-12'),
('VC-LK-053', 'Priya Kim', false, 'DONATED BY
PRIYA KIM', '2026-05-07', '2027-05-06'),
('VC-LK-055', 'Omar Morales', false, 'REST A WHILE.
— MARIA MORALES', '2026-04-29', '2026-10-28'),
('VC-LK-055', 'Victor Okafor', false, '', '2024-04-29', '2026-04-28'),
('VC-LK-056', 'James Delgado', false, 'FOR JAMES DELGADO
WHO WALKED HERE EVERY MORNING', '2026-05-12', '2027-05-11'),
('VC-LK-057', 'Riverdale Running Club', false, 'IN LOVING MEMORY OF
RIVERDALE RUNNING CLUB', '2025-02-22', '2035-02-21'),
('VC-LK-058', 'Samuel Santos', false, 'FOR LUIS KIM
WHO WALKED HERE EVERY MORNING', '2026-09-16', '2027-03-15'),
('VC-PT-001', 'Luis O''Brien', false, 'REST A WHILE.
— LUIS O''BRIEN', '2025-02-16', '2027-02-15'),
('VC-PT-006', 'Daniel Kim', false, 'REST A WHILE.
— DANIEL KIM', '2021-12-01', '2026-11-30'),
('VC-PT-006', 'Priya Goldberg', false, '', '2019-12-01', '2021-11-30'),
('VC-PT-010', 'Daniel Delgado', false, 'REST A WHILE.
— DANIEL DELGADO', '2026-07-10', '2027-01-09'),
('VC-PT-013', 'Tom Patel', false, 'IN LOVING MEMORY OF
TOM PATEL', '2018-09-12', '2028-09-11'),
('VC-PT-014', 'Tom Feldman', false, 'IN LOVING MEMORY OF
TOM FELDMAN', '2025-07-12', '2028-07-11'),
('VC-PT-016', 'James Rivera', false, 'FOR JAMES RIVERA
WHO WALKED HERE EVERY MORNING', '2025-11-21', '2027-11-20'),
('VC-PT-017', 'Maria O''Brien', false, 'DONATED BY
SAMUEL PATEL', '2026-01-26', '2029-01-25'),
('VC-PT-018', 'Priya Santos', false, 'DONATED BY
PRIYA SANTOS', '2026-05-21', '2026-11-20'),
('VC-PT-018', 'Kingsbridge Garden Society', false, 'DONATED BY
KINGSBRIDGE GARDEN SOCIETY', '2026-11-21', '2027-11-20'),
('VC-PT-019', 'Maria Adeyemi', false, 'IN LOVING MEMORY OF
LUIS FELDMAN', '2026-07-02', '2027-07-01'),
('VC-PT-021', 'Victor Patel', true, 'REST A WHILE.
— TOM FELDMAN', '2023-07-30', '2028-07-29'),
('VC-PT-024', 'Daniel Patel', false, 'REST A WHILE.
— DANIEL PATEL', '2025-10-30', '2026-10-29'),
('VC-PT-027', 'Kingsbridge Garden Society', false, '', '2026-11-08', '2027-11-07'),
('VC-PT-030', 'Bronx Birders', false, '', '2026-11-07', '2027-11-06'),
('VC-PT-031', 'Aisha Okafor', false, 'REST A WHILE.
— AISHA OKAFOR', '2025-03-07', '2027-03-06'),
('VC-PT-031', 'Yolanda Adeyemi', false, '', '2023-03-07', '2025-03-06'),
('VC-PT-033', 'Friends of Van Cortlandt Park', false, '', '2026-11-25', '2027-11-24'),
('VC-PT-035', 'James Rivera', false, 'FOR LUIS PATEL
WHO WALKED HERE EVERY MORNING', '2026-05-22', '2029-05-21'),
('VC-PT-036', 'Hannah Santos', false, 'IN LOVING MEMORY OF
AISHA SANTOS', '2026-04-19', '2028-04-18'),
('VC-PT-046', 'Aisha O''Brien', false, 'DONATED BY
AISHA O''BRIEN', '2020-04-30', '2030-04-29'),
('VC-PT-050', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-11-23', '2027-11-22'),
('VC-SH-001', 'Grace Delgado', false, 'REST A WHILE.
— MARIA MORALES', '2025-03-11', '2027-03-10'),
('VC-SH-008', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-11-15', '2027-11-14'),
('VC-SH-009', 'Priya Goldberg', false, 'FOR PRIYA GOLDBERG
WHO WALKED HERE EVERY MORNING', '2026-08-11', '2027-08-10'),
('VC-SH-013', 'Beatriz Rivera', false, 'DONATED BY
BEATRIZ RIVERA', '2023-03-23', '2028-03-22'),
('VC-SH-013', 'Omar Delgado', false, '', '2021-03-23', '2023-03-22'),
('VC-SH-026', 'Beatriz Morales', false, 'DONATED BY
BEATRIZ MORALES', '2026-06-22', '2029-06-21'),
('VC-SH-027', 'Rosa Rivera', false, 'REST A WHILE.
— ROSA RIVERA', '2026-03-21', '2027-03-20'),
('VC-SH-027', 'James Nguyen', false, '', '2024-03-21', '2026-03-20'),
('VC-SH-031', 'Tom Feldman', false, 'REST A WHILE.
— TOM FELDMAN', '2026-09-01', '2027-08-31'),
('VC-SH-032', 'Yolanda Morales', false, 'FOR PRIYA PATEL
WHO WALKED HERE EVERY MORNING', '2026-05-20', '2026-11-19'),
('VC-SH-033', 'Samuel Feldman', false, 'REST A WHILE.
— SAMUEL FELDMAN', '2025-10-04', '2026-10-03'),
('VC-SH-035', 'Friends of Van Cortlandt Park', false, 'REST A WHILE.
— DANIEL NGUYEN', '2020-12-08', '2030-12-07'),
('VC-SH-036', 'Tom Santos', false, 'REST A WHILE.
— TOM SANTOS', '2026-03-08', '2028-03-07'),
('VC-SH-036', 'Daniel Morales', false, '', '2024-03-08', '2026-03-07'),
('VC-SH-039', 'Yolanda Santos', false, 'IN LOVING MEMORY OF
ROSA RIVERA', '2022-05-06', '2032-05-05'),
('VC-SH-041', 'Luis Okafor', false, 'DONATED BY
KEVIN SANTOS', '2024-03-23', '2027-03-22'),
('VC-SH-041', 'Hannah Rivera', false, '', '2022-03-23', '2024-03-22'),
('VC-SH-043', 'Riverdale Running Club', false, 'FOR DANIEL GOLDBERG
WHO WALKED HERE EVERY MORNING', '2026-05-01', '2026-10-31'),
('VC-SH-043', 'Beatriz Nguyen', false, '', '2024-05-01', '2026-04-30'),
('VC-AQ-004', 'Hannah Okafor', false, 'FOR BEATRIZ ADEYEMI
WHO WALKED HERE EVERY MORNING', '2023-05-19', '2028-05-18'),
('VC-AQ-004', 'Grace Kim', false, '', '2021-05-19', '2023-05-18'),
('VC-AQ-006', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-10-14', '2027-10-13'),
('VC-AQ-009', 'Bronx Birders', false, 'IN LOVING MEMORY OF
DANIEL SANTOS', '2026-04-01', '2027-03-31'),
('VC-AQ-011', 'Victor Okafor', false, 'DONATED BY
VICTOR OKAFOR', '2023-04-03', '2028-04-02'),
('VC-AQ-012', 'Riverdale Running Club', false, '', '2026-10-17', '2027-10-16'),
('VC-AQ-013', 'Yolanda Patel', false, 'DONATED BY
YOLANDA PATEL', '2026-08-03', '2027-08-02'),
('VC-AQ-014', 'Omar Patel', false, 'FOR LUIS GOLDBERG
WHO WALKED HERE EVERY MORNING', '2017-02-18', '2027-02-17'),
('VC-AQ-020', 'Priya Rivera', false, 'DONATED BY
KEVIN NGUYEN', '2026-08-08', '2028-08-07'),
('VC-AQ-020', 'Maria Rivera', false, '', '2024-08-08', '2026-08-07'),
('VC-AQ-021', 'Tom Morales', false, 'IN LOVING MEMORY OF
JAMES MORALES', '2023-09-27', '2033-09-26'),
('VC-AQ-022', 'Maria Santos', false, 'DONATED BY
MARIA SANTOS', '2026-05-30', '2026-11-29'),
('VC-AQ-024', 'Kevin Kim', false, 'DONATED BY
AISHA O''BRIEN', '2026-01-03', '2028-01-02'),
('VC-AQ-030', 'Luis Kim', false, 'FOR LUIS KIM
WHO WALKED HERE EVERY MORNING', '2026-04-08', '2026-10-07'),
('VC-AQ-032', 'Beatriz Kim', false, 'REST A WHILE.
— BEATRIZ KIM', '2025-06-08', '2027-06-07'),
('VC-AQ-036', 'James Santos', false, 'REST A WHILE.
— JAMES SANTOS', '2024-11-07', '2026-11-06'),
('VC-AQ-037', 'Hannah Delgado', true, 'DONATED BY
HANNAH DELGADO', '2023-07-12', '2033-07-11'),
('VC-AQ-039', 'Hannah Goldberg', false, 'DONATED BY
HANNAH GOLDBERG', '2026-06-15', '2027-06-14'),
('VC-AQ-040', 'Luis Delgado', false, 'IN LOVING MEMORY OF
LUIS ADEYEMI', '2017-06-07', '2027-06-06'),
('VC-AQ-045', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-12-01', '2027-11-30'),
('VC-TB-002', 'Riverdale Running Club', false, 'FOR GRACE OKAFOR
WHO WALKED HERE EVERY MORNING', '2026-09-22', '2029-09-21'),
('VC-TB-002', 'Aisha Santos', false, '', '2024-09-22', '2026-09-21'),
('VC-TB-003', 'Yolanda Rivera', false, 'IN LOVING MEMORY OF
LUIS OKAFOR', '2026-04-25', '2029-04-24'),
('VC-TB-003', 'Maria Goldberg', false, '', '2024-04-25', '2026-04-24'),
('VC-TB-006', 'Kevin Nguyen', true, 'REST A WHILE.
— KEVIN NGUYEN', '2026-09-22', '2027-03-21'),
('VC-TB-006', 'Priya Adeyemi', false, '', '2024-09-22', '2026-09-21'),
('VC-TB-009', 'Luis Okafor', false, 'FOR VICTOR RIVERA
WHO WALKED HERE EVERY MORNING', '2026-09-20', '2027-09-19'),
('VC-TB-009', 'Victor Nguyen', false, '', '2024-09-20', '2026-09-19'),
('VC-TB-011', 'Grace Goldberg', false, 'IN LOVING MEMORY OF
GRACE GOLDBERG', '2026-05-03', '2026-11-02'),
('VC-TB-013', 'Samuel Patel', false, 'IN LOVING MEMORY OF
OMAR OKAFOR', '2019-11-26', '2029-11-25'),
('VC-TB-015', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-12-30', '2027-12-29'),
('VC-TB-016', 'Rosa Goldberg', false, 'DONATED BY
HANNAH PATEL', '2023-12-22', '2033-12-21'),
('VC-TB-018', 'Aisha Delgado', false, 'REST A WHILE.
— LUIS SANTOS', '2023-07-18', '2028-07-17'),
('VC-TB-019', 'Samuel Patel', false, 'IN LOVING MEMORY OF
SAMUEL PATEL', '2022-02-27', '2027-02-26'),
('VC-TB-020', 'Rosa Feldman', false, 'FOR ROSA FELDMAN
WHO WALKED HERE EVERY MORNING', '2025-12-11', '2026-12-10'),
('VC-TB-021', 'Grace Rivera', false, 'IN LOVING MEMORY OF
LUIS GOLDBERG', '2019-04-25', '2029-04-24'),
('VC-TB-022', 'Victor Patel', false, 'FOR VICTOR PATEL
WHO WALKED HERE EVERY MORNING', '2024-10-28', '2026-10-27'),
('VC-TB-025', 'Priya Feldman', true, 'FOR SAMUEL GOLDBERG
WHO WALKED HERE EVERY MORNING', '2026-07-22', '2028-07-21'),
('VC-TB-025', 'Omar Okafor', false, '', '2024-07-22', '2026-07-21'),
('VC-TB-026', 'Luis Morales', false, 'DONATED BY
LUIS MORALES', '2025-06-22', '2027-06-21'),
('VC-TB-030', 'Maria Adeyemi', false, 'DONATED BY
GRACE RIVERA', '2026-06-13', '2026-12-12'),
('VC-TB-031', 'Luis Rivera', false, 'FOR OMAR GOLDBERG
WHO WALKED HERE EVERY MORNING', '2026-05-21', '2028-05-20'),
('VC-TB-035', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-11-10', '2027-11-09'),
('VC-TB-037', 'Victor Adeyemi', true, 'REST A WHILE.
— JAMES OKAFOR', '2026-03-02', '2027-03-01'),
('VC-TB-038', 'Rosa O''Brien', false, 'IN LOVING MEMORY OF
ROSA O''BRIEN', '2026-08-23', '2027-08-22'),
('VC-TB-038', 'Priya Okafor', false, '', '2024-08-23', '2026-08-22'),
('VC-TB-039', 'Daniel Santos', false, 'DONATED BY
GRACE PATEL', '2026-05-17', '2026-11-16'),
('VC-TB-040', 'Tom Nguyen', false, 'REST A WHILE.
— PRIYA ADEYEMI', '2022-02-27', '2027-02-26'),
('VC-ST-004', 'Grace Okafor', false, 'DONATED BY
OMAR RIVERA', '2026-06-23', '2026-12-22'),
('VC-ST-005', 'Kingsbridge Garden Society', false, 'IN LOVING MEMORY OF
KINGSBRIDGE GARDEN SOCIETY', '2026-09-14', '2027-09-13'),
('VC-ST-005', 'Friends of Van Cortlandt Park', false, 'DONATED BY
FRIENDS OF VAN CORTLANDT PARK', '2027-09-14', '2028-09-13'),
('VC-ST-006', 'Class of 1998, DeWitt Clinton HS', false, 'IN LOVING MEMORY OF
CLASS OF 1998, DEWITT CLINTON HS', '2018-04-02', '2028-04-01'),
('VC-ST-010', 'Bronx Birders', true, 'REST A WHILE.
— VICTOR MORALES', '2026-08-11', '2027-08-10'),
('VC-ST-013', 'Tom Feldman', false, 'DONATED BY
SAMUEL ADEYEMI', '2026-04-16', '2027-04-15'),
('VC-ST-013', 'Aisha Morales', false, '', '2024-04-16', '2026-04-15'),
('VC-ST-016', 'Daniel Adeyemi', true, 'IN LOVING MEMORY OF
DANIEL ADEYEMI', '2025-04-25', '2027-04-24'),
('VC-ST-018', 'Class of 1998, DeWitt Clinton HS', false, 'DONATED BY
CLASS OF 1998, DEWITT CLINTON HS', '2026-07-29', '2027-01-28'),
('VC-ST-019', 'Bronx Birders', false, '', '2026-11-17', '2027-11-16'),
('VC-ST-025', 'Class of 1998, DeWitt Clinton HS', false, 'FOR CLASS OF 1998, DEWITT CLINTON HS
WHO WALKED HERE EVERY MORNING', '2024-11-12', '2026-11-11'),
('VC-ST-025', 'Aisha Feldman', false, '', '2022-11-12', '2024-11-11'),
('VC-ST-025', 'Friends of Van Cortlandt Park', false, 'DONATED BY
BRONX BIRDERS', '2026-11-12', '2027-11-11'),
('VC-ST-027', 'Aisha Feldman', false, 'DONATED BY
AISHA FELDMAN', '2026-04-18', '2026-10-17'),
('VC-ST-027', 'Grace Santos', false, '', '2024-04-18', '2026-04-17'),
('VC-ST-029', 'Samuel Delgado', false, 'DONATED BY
SAMUEL DELGADO', '2019-10-31', '2029-10-30'),
('VC-ST-029', 'Aisha Santos', false, '', '2017-10-31', '2019-10-30'),
('VC-ST-033', 'Priya Morales', false, 'FOR PRIYA MORALES
WHO WALKED HERE EVERY MORNING', '2026-04-22', '2027-04-21'),
('VC-ST-033', 'Maria O''Brien', false, '', '2024-04-22', '2026-04-21'),
('VC-ST-035', 'Samuel Okafor', false, 'REST A WHILE.
— SAMUEL OKAFOR', '2025-04-26', '2028-04-25'),
('VC-NW-003', 'Luis Okafor', false, 'IN LOVING MEMORY OF
SAMUEL RIVERA', '2024-05-07', '2027-05-06'),
('VC-NW-004', 'Victor Rivera', false, 'REST A WHILE.
— SAMUEL KIM', '2026-07-18', '2027-07-17'),
('VC-NW-004', 'Omar Okafor', false, '', '2024-07-18', '2026-07-17'),
('VC-NW-005', 'Victor Nguyen', false, 'REST A WHILE.
— VICTOR NGUYEN', '2025-12-08', '2026-12-07'),
('VC-NW-005', 'Daniel Morales', false, '', '2023-12-08', '2025-12-07'),
('VC-NW-006', 'Class of 1998, DeWitt Clinton HS', false, '', '2027-01-13', '2028-01-12'),
('VC-NW-009', 'Hannah Nguyen', false, 'REST A WHILE.
— GRACE O''BRIEN', '2026-05-10', '2027-05-09'),
('VC-NW-011', 'Samuel Kim', false, 'DONATED BY
SAMUEL KIM', '2024-05-24', '2027-05-23'),
('VC-NW-011', 'Aisha Patel', false, '', '2022-05-24', '2024-05-23'),
('VC-NW-012', 'Yolanda Delgado', false, 'IN LOVING MEMORY OF
VICTOR RIVERA', '2026-02-22', '2027-02-21'),
('VC-NW-017', 'Yolanda Rivera', false, 'FOR OMAR FELDMAN
WHO WALKED HERE EVERY MORNING', '2025-01-30', '2027-01-29'),
('VC-NW-018', 'Luis Nguyen', false, 'IN LOVING MEMORY OF
GRACE NGUYEN', '2024-10-16', '2026-10-15'),
('VC-NW-018', 'Yolanda Kim', false, '', '2022-10-16', '2024-10-15'),
('VC-NW-019', 'Maria Delgado', false, 'FOR MARIA DELGADO
WHO WALKED HERE EVERY MORNING', '2024-05-09', '2027-05-08'),
('VC-NW-019', 'James Rivera', false, '', '2022-05-09', '2024-05-08'),
('VC-NW-019', 'Class of 1998, DeWitt Clinton HS', false, 'DONATED BY
CLASS OF 1998, DEWITT CLINTON HS', '2027-05-09', '2028-05-08'),
('VC-NW-021', 'Riverdale Running Club', false, 'IN LOVING MEMORY OF
TOM KIM', '2026-08-22', '2027-08-21'),
('VC-NW-021', 'Grace Rivera', false, '', '2024-08-22', '2026-08-21'),
('VC-NW-022', 'James O''Brien', false, 'IN LOVING MEMORY OF
JAMES O''BRIEN', '2023-10-13', '2028-10-12'),
('VC-NW-023', 'Rosa Nguyen', false, 'DONATED BY
ROSA NGUYEN', '2026-05-14', '2026-11-13'),
('VC-NW-024', 'Class of 1998, DeWitt Clinton HS', false, 'FOR LUIS MORALES
WHO WALKED HERE EVERY MORNING', '2026-04-28', '2026-10-27'),
('VC-NW-026', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-10-30', '2027-10-29'),
('VC-NW-029', 'Priya Kim', false, 'REST A WHILE.
— PRIYA KIM', '2024-05-21', '2029-05-20'),
('VC-NW-030', 'Omar Morales', false, 'IN LOVING MEMORY OF
LUIS O''BRIEN', '2019-12-20', '2029-12-19'),
('VC-NW-030', 'Beatriz Rivera', false, '', '2017-12-20', '2019-12-19'),
('VC-NW-031', 'James Patel', false, 'REST A WHILE.
— JAMES PATEL', '2025-12-06', '2026-12-05'),
('VC-NW-031', 'Rosa O''Brien', false, '', '2023-12-06', '2025-12-05'),
('VC-NW-032', 'Yolanda O''Brien', false, 'FOR DANIEL FELDMAN
WHO WALKED HERE EVERY MORNING', '2025-07-06', '2028-07-05'),
('VC-NW-035', 'Luis Nguyen', false, 'DONATED BY
LUIS NGUYEN', '2025-10-05', '2026-10-04'),
('VC-JK-002', 'Omar O''Brien', false, 'REST A WHILE.
— OMAR FELDMAN', '2026-01-13', '2027-01-12'),
('VC-JK-003', 'James Kim', false, 'IN LOVING MEMORY OF
JAMES KIM', '2025-10-15', '2026-10-14'),
('VC-JK-008', 'Bronx Birders', false, 'IN LOVING MEMORY OF
BRONX BIRDERS', '2023-12-20', '2026-12-19'),
('VC-JK-008', 'Omar Nguyen', false, '', '2021-12-20', '2023-12-19'),
('VC-JK-010', 'Bronx Birders', false, '', '2026-10-22', '2027-10-21'),
('VC-JK-011', 'Omar Delgado', false, 'REST A WHILE.
— OMAR DELGADO', '2024-07-25', '2029-07-24'),
('VC-JK-012', 'Beatriz Okafor', false, 'IN LOVING MEMORY OF
BEATRIZ OKAFOR', '2025-05-26', '2028-05-25'),
('VC-JK-015', 'Luis Nguyen', false, 'REST A WHILE.
— JAMES O''BRIEN', '2025-11-03', '2026-11-02'),
('VC-JK-017', 'Yolanda Kim', true, 'FOR YOLANDA KIM
WHO WALKED HERE EVERY MORNING', '2026-05-13', '2027-05-12'),
('VC-JK-018', 'Kingsbridge Garden Society', false, 'IN LOVING MEMORY OF
KINGSBRIDGE GARDEN SOCIETY', '2025-11-14', '2026-11-13'),
('VC-JK-019', 'Samuel Morales', false, 'REST A WHILE.
— SAMUEL MORALES', '2026-03-10', '2029-03-09'),
('VC-JK-020', 'Grace Feldman', false, 'REST A WHILE.
— VICTOR DELGADO', '2025-11-29', '2026-11-28'),
('VC-JK-022', 'Bronx Birders', false, 'REST A WHILE.
— BRONX BIRDERS', '2026-02-26', '2031-02-25'),
('VC-JK-026', 'Rosa Goldberg', false, 'IN LOVING MEMORY OF
DANIEL KIM', '2025-10-09', '2027-10-08'),
('VC-JK-026', 'Victor Nguyen', false, '', '2023-10-09', '2025-10-08'),
('VC-JK-027', 'Kevin Goldberg', false, 'REST A WHILE.
— KEVIN GOLDBERG', '2025-04-27', '2027-04-26'),
('VC-JK-028', 'Riverdale Running Club', false, 'REST A WHILE.
— RIVERDALE RUNNING CLUB', '2026-07-13', '2027-07-12'),
('VC-JK-031', 'Tom Rivera', false, 'FOR TOM RIVERA
WHO WALKED HERE EVERY MORNING', '2026-08-21', '2027-02-20'),
('VC-JK-032', 'Kevin Nguyen', false, 'REST A WHILE.
— KEVIN NGUYEN', '2026-06-29', '2027-06-28'),
('VC-JK-033', 'Aisha Goldberg', false, 'FOR HANNAH KIM
WHO WALKED HERE EVERY MORNING', '2025-09-30', '2026-09-29'),
('VC-JK-033', 'Daniel Morales', false, '', '2023-09-30', '2025-09-29'),
('VC-JK-034', 'Hannah Okafor', false, 'IN LOVING MEMORY OF
OMAR GOLDBERG', '2026-01-14', '2027-01-13'),
('VC-JK-035', 'Aisha Adeyemi', false, 'REST A WHILE.
— AISHA ADEYEMI', '2026-04-19', '2026-10-18'),
('VC-HM-001', 'Samuel Patel', false, 'REST A WHILE.
— SAMUEL PATEL', '2025-10-20', '2027-10-19'),
('VC-HM-004', 'Priya Delgado', true, 'DONATED BY
PRIYA DELGADO', '2023-11-23', '2026-11-22'),
('VC-HM-005', 'Class of 1998, DeWitt Clinton HS', false, 'REST A WHILE.
— MARIA NGUYEN', '2025-12-23', '2027-12-22'),
('VC-HM-005', 'Beatriz Kim', false, '', '2023-12-23', '2025-12-22'),
('VC-HM-007', 'Aisha Delgado', true, 'DONATED BY
MARIA O''BRIEN', '2024-01-12', '2034-01-11'),
('VC-HM-008', 'Yolanda Adeyemi', false, 'REST A WHILE.
— YOLANDA ADEYEMI', '2026-09-07', '2027-03-06'),
('VC-HM-008', 'Maria Patel', false, '', '2024-09-07', '2026-09-06'),
('VC-HM-010', 'Class of 1998, DeWitt Clinton HS', false, '', '2026-12-28', '2027-12-27'),
('VC-HM-011', 'Yolanda Santos', false, 'IN LOVING MEMORY OF
YOLANDA SANTOS', '2026-05-22', '2026-11-21'),
('VC-HM-011', 'Yolanda Delgado', false, '', '2024-05-22', '2026-05-21'),
('VC-HM-012', 'Bronx Birders', false, 'FOR TOM NGUYEN
WHO WALKED HERE EVERY MORNING', '2026-01-22', '2027-01-21'),
('VC-HM-012', 'Kingsbridge Garden Society', false, 'DONATED BY
FRIENDS OF VAN CORTLANDT PARK', '2027-01-22', '2028-01-21'),
('VC-HM-012', 'Beatriz Morales', false, '', '2028-01-22', '2029-01-21'),
('VC-HM-012', 'Yolanda Nguyen', false, '', '2029-01-22', '2031-01-21'),
('VC-HM-014', 'Bronx Birders', false, 'DONATED BY
LUIS OKAFOR', '2025-10-18', '2026-10-17'),
('VC-HM-015', 'Kingsbridge Garden Society', false, 'FOR ROSA KIM
WHO WALKED HERE EVERY MORNING', '2025-04-12', '2027-04-11'),
('VC-HM-020', 'Luis Rivera', false, 'FOR AISHA FELDMAN
WHO WALKED HERE EVERY MORNING', '2025-03-31', '2027-03-30'),
('VC-HM-023', 'Riverdale Running Club', false, '', '2027-01-25', '2028-01-24'),
('VC-HM-025', 'Samuel Delgado', false, 'FOR SAMUEL DELGADO
WHO WALKED HERE EVERY MORNING', '2026-09-03', '2027-03-02'),
('VC-HM-027', 'Kingsbridge Garden Society', false, 'DONATED BY
JAMES PATEL', '2026-04-27', '2028-04-26'),
('VC-HM-027', 'Yolanda Adeyemi', false, '', '2024-04-27', '2026-04-26'),
('VC-HM-030', 'James Nguyen', false, 'REST A WHILE.
— JAMES NGUYEN', '2026-07-21', '2028-07-20'),
('VC-VH-001', 'Bronx Birders', false, 'REST A WHILE.
— KEVIN RIVERA', '2020-01-26', '2030-01-25'),
('VC-VH-003', 'Omar Goldberg', false, 'FOR VICTOR OKAFOR
WHO WALKED HERE EVERY MORNING', '2026-08-24', '2028-08-23'),
('VC-VH-003', 'Riverdale Running Club', false, 'DONATED BY
KINGSBRIDGE GARDEN SOCIETY', '2028-08-24', '2029-08-23'),
('VC-VH-003', 'Kevin O''Brien', false, '', '2029-08-24', '2030-08-23'),
('VC-VH-003', 'Beatriz Nguyen', false, '', '2030-08-24', '2031-02-23'),
('VC-VH-009', 'Aisha Feldman', false, 'IN LOVING MEMORY OF
AISHA GOLDBERG', '2026-07-29', '2027-07-28'),
('VC-VH-009', 'Samuel Adeyemi', false, '', '2024-07-29', '2026-07-28'),
('VC-VH-013', 'Aisha Delgado', false, 'REST A WHILE.
— ROSA FELDMAN', '2026-02-16', '2027-02-15'),
('VC-VH-013', 'Daniel Goldberg', false, '', '2024-02-16', '2026-02-15'),
('VC-VH-015', 'Priya Kim', false, 'FOR KEVIN NGUYEN
WHO WALKED HERE EVERY MORNING', '2026-01-15', '2027-01-14'),
('VC-VH-016', 'Beatriz Adeyemi', true, 'FOR AISHA MORALES
WHO WALKED HERE EVERY MORNING', '2026-01-12', '2027-01-11'),
('VC-VH-018', 'Yolanda Nguyen', false, 'IN LOVING MEMORY OF
YOLANDA NGUYEN', '2025-10-04', '2030-10-03'),
('VC-VH-019', 'Riverdale Running Club', false, '', '2026-12-11', '2027-12-10'),
('VC-VH-020', 'James Adeyemi', false, 'FOR VICTOR DELGADO
WHO WALKED HERE EVERY MORNING', '2026-07-18', '2027-01-17'),
('VC-VH-024', 'Kingsbridge Garden Society', false, 'FOR KINGSBRIDGE GARDEN SOCIETY
WHO WALKED HERE EVERY MORNING', '2025-02-13', '2030-02-12'),
('VC-IF-003', 'Priya O''Brien', false, 'FOR PRIYA O''BRIEN
WHO WALKED HERE EVERY MORNING', '2026-01-18', '2031-01-17'),
('VC-IF-003', 'James Adeyemi', false, '', '2024-01-18', '2026-01-17'),
('VC-IF-004', 'James Patel', false, 'IN LOVING MEMORY OF
JAMES PATEL', '2025-08-26', '2035-08-25'),
('VC-IF-006', 'Grace Morales', false, 'REST A WHILE.
— AISHA RIVERA', '2025-01-03', '2027-01-02'),
('VC-IF-007', 'Daniel Nguyen', false, 'REST A WHILE.
— DANIEL NGUYEN', '2024-09-05', '2034-09-04'),
('VC-IF-012', 'Priya Delgado', true, 'REST A WHILE.
— BEATRIZ PATEL', '2026-03-19', '2028-03-18'),
('VC-IF-013', 'Tom Nguyen', false, 'IN LOVING MEMORY OF
JAMES PATEL', '2025-01-27', '2030-01-26'),
('VC-IF-014', 'Class of 1998, DeWitt Clinton HS', false, 'FOR CLASS OF 1998, DEWITT CLINTON HS
WHO WALKED HERE EVERY MORNING', '2026-07-16', '2027-07-15'),
('VC-IF-014', 'Omar O''Brien', false, '', '2024-07-16', '2026-07-15'),
('VC-IF-016', 'Rosa Delgado', false, 'FOR ROSA DELGADO
WHO WALKED HERE EVERY MORNING', '2026-04-06', '2026-10-05'),
('VC-IF-017', 'Victor Adeyemi', false, 'DONATED BY
VICTOR ADEYEMI', '2023-11-24', '2026-11-23'),
('VC-IF-018', 'Kevin Okafor', true, 'DONATED BY
GRACE O''BRIEN', '2026-03-03', '2029-03-02'),
('VC-IF-018', 'Grace Okafor', false, '', '2024-03-03', '2026-03-02'),
('VC-IF-019', 'Victor Okafor', false, 'FOR BEATRIZ FELDMAN
WHO WALKED HERE EVERY MORNING', '2020-07-08', '2030-07-07'),
('VC-IF-019', 'Beatriz Patel', false, '', '2018-07-08', '2020-07-07'),
('VC-IF-020', 'Yolanda Okafor', false, 'IN LOVING MEMORY OF
PRIYA MORALES', '2026-05-23', '2027-05-22'),
('VC-IF-023', 'Maria Feldman', false, 'FOR MARIA SANTOS
WHO WALKED HERE EVERY MORNING', '2026-06-13', '2026-12-12'),
('VC-IF-023', 'Aisha Feldman', false, '', '2024-06-13', '2026-06-12'),
('VC-IF-024', 'Riverdale Running Club', false, 'IN LOVING MEMORY OF
ROSA O''BRIEN', '2026-04-13', '2026-10-12'),
('VC-GC-002', 'Beatriz Feldman', false, 'FOR BEATRIZ FELDMAN
WHO WALKED HERE EVERY MORNING', '2025-12-30', '2026-12-29'),
('VC-GC-002', 'Yolanda Goldberg', false, '', '2023-12-30', '2025-12-29'),
('VC-GC-004', 'Grace Patel', false, 'REST A WHILE.
— GRACE PATEL', '2021-08-12', '2031-08-11'),
('VC-GC-007', 'Rosa Goldberg', false, 'IN LOVING MEMORY OF
ROSA GOLDBERG', '2026-08-15', '2027-02-14'),
('VC-GC-009', 'Omar Okafor', false, 'IN LOVING MEMORY OF
OMAR OKAFOR', '2026-07-24', '2029-07-23'),
('VC-GC-012', 'Kingsbridge Garden Society', false, '', '2026-11-15', '2027-11-14'),
('VC-GC-014', 'Daniel Santos', false, 'REST A WHILE.
— BEATRIZ SANTOS', '2026-09-15', '2027-03-14'),
('VC-GC-017', 'Bronx Birders', true, 'DONATED BY
BRONX BIRDERS', '2022-10-18', '2032-10-17'),
('VC-GC-020', 'Kevin Rivera', false, 'FOR LUIS NGUYEN
WHO WALKED HERE EVERY MORNING', '2022-09-07', '2027-09-06');
