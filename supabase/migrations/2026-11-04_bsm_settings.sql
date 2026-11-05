-- BSM live-show pointer — one settings row that says which episode is "live" on the permanent
-- screens (tv.html / crew.html / host.html). Additive only: creates ONE new table; no existing
-- table, row, or policy is modified.
--
-- Backups taken before this was written (beb/backups/):
--   builder_state-ALL-backup-2026-11-04_230056.json   (all 9 rows)
--   show_state-ALL-backup-2026-11-04_230056.json      (row 1)
--
-- Apply: Supabase dashboard → SQL Editor → paste this whole file → Run.
-- Undo:  drop table public.bsm_settings;   (nothing else depends on it)

begin;

create table public.bsm_settings (
  id           smallint primary key default 1 check (id = 1),           -- exactly one row, ever
  live_show_id integer references public.builder_state(id) on delete set null,  -- episode row (E12 = 12)
  updated_at   timestamptz not null default now()
);

insert into public.bsm_settings (id, live_show_id) values (1, null);     -- empty = LBV holding screen

alter table public.bsm_settings enable row level security;

-- Screens read it; the BSM "Set as live" button updates it. Nobody can insert or delete rows.
create policy "bsm_settings: read"     on public.bsm_settings for select to anon, authenticated using (true);
create policy "bsm_settings: set live" on public.bsm_settings for update to anon, authenticated
  using (id = 1) with check (id = 1);

-- Push changes to the screens instantly.
alter publication supabase_realtime add table public.bsm_settings;

commit;
