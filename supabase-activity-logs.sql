create table if not exists public.activity_logs (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  action text not null check (char_length(action) <= 40),
  page text not null check (char_length(page) <= 40),
  target text not null default '' check (char_length(target) <= 100)
);

create table if not exists public.log_admins (
  email text primary key check (email = lower(email))
);

alter table public.activity_logs enable row level security;
alter table public.log_admins enable row level security;

revoke all on public.activity_logs from anon, authenticated;
revoke all on public.log_admins from anon, authenticated;
grant insert (action, page, target) on public.activity_logs to anon, authenticated;
grant select, delete on public.activity_logs to authenticated;
grant usage, select on sequence public.activity_logs_id_seq to anon, authenticated;

create or replace function public.is_log_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.log_admins
    where email = lower(auth.jwt() ->> 'email')
  );
$$;

revoke all on function public.is_log_admin() from public;
grant execute on function public.is_log_admin() to authenticated;

drop policy if exists "Visitors can submit limited activity" on public.activity_logs;
create policy "Visitors can submit limited activity"
on public.activity_logs
for insert
to anon, authenticated
with check (
  action in ('Click', 'Login succeeded', 'Login failed', 'Opened envelope', 'Logged out', 'Cleared activity logs')
  and page in ('index.html', 'diary.html', 'logs.html')
  and char_length(target) <= 100
);

drop policy if exists "Only the listed owner can view activity" on public.activity_logs;
create policy "Only the listed owner can view activity"
on public.activity_logs
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can clear activity" on public.activity_logs;
create policy "Only the listed owner can clear activity"
on public.activity_logs
for delete
to authenticated
using ((select public.is_log_admin()));

-- After creating your Supabase Auth user, add its email as the only log admin:
-- insert into public.log_admins (email) values (lower('YOUR_EMAIL_ADDRESS'));
