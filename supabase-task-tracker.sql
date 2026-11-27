-- Per-user task boards, comments, activity history, and admin user selection.

create table if not exists public.task_tracker_tasks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 140),
  contents text not null default '' check (char_length(contents) <= 5000),
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'completed')),
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high')),
  deadline timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$
declare
  v_deadline_type text;
begin
  select c.data_type into v_deadline_type
  from information_schema.columns as c
  where c.table_schema = 'public'
    and c.table_name = 'task_tracker_tasks'
    and c.column_name = 'deadline';

  if v_deadline_type = 'date' then
    alter table public.task_tracker_tasks
      alter column deadline type timestamptz
      using (deadline::timestamp + interval '23 hours 59 minutes') at time zone 'Asia/Manila';
  end if;
end;
$$;

create table if not exists public.task_tracker_subtasks (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.task_tracker_tasks(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 300),
  is_completed boolean not null default false,
  position integer not null default 0 check (position >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.task_tracker_comments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.task_tracker_tasks(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  author_id uuid not null,
  author_email text not null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.task_tracker_activity (
  id bigint generated always as identity primary key,
  task_id uuid not null,
  owner_id uuid not null,
  task_title text not null,
  action text not null,
  summary text not null,
  actor_id uuid,
  actor_email text not null,
  created_at timestamptz not null default now()
);

create index if not exists task_tracker_tasks_owner_status_idx
  on public.task_tracker_tasks (owner_id, status, created_at);
create index if not exists task_tracker_subtasks_task_position_idx
  on public.task_tracker_subtasks (task_id, position, created_at);
create index if not exists task_tracker_comments_task_created_idx
  on public.task_tracker_comments (task_id, created_at);
create index if not exists task_tracker_activity_owner_created_idx
  on public.task_tracker_activity (owner_id, created_at desc);
create index if not exists task_tracker_activity_task_created_idx
  on public.task_tracker_activity (task_id, created_at desc);

alter table public.task_tracker_tasks enable row level security;
alter table public.task_tracker_subtasks enable row level security;
alter table public.task_tracker_comments enable row level security;
alter table public.task_tracker_activity enable row level security;

revoke all on public.task_tracker_tasks, public.task_tracker_subtasks,
  public.task_tracker_comments, public.task_tracker_activity
  from public, anon, authenticated;
grant select, insert, update, delete on public.task_tracker_tasks to authenticated;
grant select, insert, update, delete on public.task_tracker_subtasks to authenticated;
grant select, insert on public.task_tracker_comments to authenticated;
grant select on public.task_tracker_activity to authenticated;

drop policy if exists "Task owners and admins manage tasks" on public.task_tracker_tasks;
create policy "Task owners and admins manage tasks"
on public.task_tracker_tasks for all to authenticated
using (owner_id = (select auth.uid()) or (select public.is_log_admin()))
with check (owner_id = (select auth.uid()) or (select public.is_log_admin()));

drop policy if exists "Task owners and admins manage subtasks" on public.task_tracker_subtasks;
create policy "Task owners and admins manage subtasks"
on public.task_tracker_subtasks for all to authenticated
using (owner_id = (select auth.uid()) or (select public.is_log_admin()))
with check (owner_id = (select auth.uid()) or (select public.is_log_admin()));

drop policy if exists "Task owners and admins view comments" on public.task_tracker_comments;
create policy "Task owners and admins view comments"
on public.task_tracker_comments for select to authenticated
using (owner_id = (select auth.uid()) or (select public.is_log_admin()));

drop policy if exists "Task owners and admins add comments" on public.task_tracker_comments;
create policy "Task owners and admins add comments"
on public.task_tracker_comments for insert to authenticated
with check (owner_id = (select auth.uid()) or (select public.is_log_admin()));

drop policy if exists "Task owners and admins view activity" on public.task_tracker_activity;
create policy "Task owners and admins view activity"
on public.task_tracker_activity for select to authenticated
using (owner_id = (select auth.uid()) or (select public.is_log_admin()));

create or replace function public.task_tracker_set_child_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if tg_op = 'UPDATE' and new.task_id is distinct from old.task_id then
    raise exception 'A task item cannot be moved to another task.';
  end if;

  select t.owner_id into v_owner_id
  from public.task_tracker_tasks as t
  where t.id = new.task_id;

  if not found then
    raise exception 'The selected task does not exist.';
  end if;

  new.owner_id := v_owner_id;
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
  end if;
  if tg_table_name = 'task_tracker_comments' then
    new.author_id := auth.uid();
    new.author_email := coalesce(nullif(auth.jwt() ->> 'email', ''), 'User');
  end if;
  return new;
end;
$$;

revoke all on function public.task_tracker_set_child_fields() from public, anon, authenticated;

drop trigger if exists task_tracker_set_subtask_fields on public.task_tracker_subtasks;
create trigger task_tracker_set_subtask_fields
before insert or update on public.task_tracker_subtasks
for each row execute function public.task_tracker_set_child_fields();

drop trigger if exists task_tracker_set_comment_fields on public.task_tracker_comments;
create trigger task_tracker_set_comment_fields
before insert on public.task_tracker_comments
for each row execute function public.task_tracker_set_child_fields();

create or replace function public.task_tracker_touch_task()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    new.updated_at := new.created_at;
    return new;
  end if;
  if new.owner_id is distinct from old.owner_id then
    raise exception 'A task cannot be moved to another user board.';
  end if;
  new.created_at := old.created_at;
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.task_tracker_touch_task() from public, anon, authenticated;
drop trigger if exists task_tracker_touch_task on public.task_tracker_tasks;
create trigger task_tracker_touch_task
before insert or update on public.task_tracker_tasks
for each row execute function public.task_tracker_touch_task();

create or replace function public.task_tracker_log_task_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text := coalesce(nullif(auth.jwt() ->> 'email', ''), 'User');
begin
  if tg_op = 'INSERT' then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (new.id, new.owner_id, new.title, 'task_created', 'Created this task', auth.uid(), v_email);
    return new;
  elsif tg_op = 'DELETE' then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (old.id, old.owner_id, old.title, 'task_deleted', 'Deleted this task', auth.uid(), v_email);
    return old;
  end if;

  if new.title is distinct from old.title or new.contents is distinct from old.contents then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (new.id, new.owner_id, new.title, 'task_edited', 'Edited task details', auth.uid(), v_email);
  end if;
  if new.status is distinct from old.status then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (new.id, new.owner_id, new.title, 'status_changed',
       'Moved task to ' || replace(new.status, '_', ' '), auth.uid(), v_email);
  end if;
  if new.priority is distinct from old.priority then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (new.id, new.owner_id, new.title, 'priority_changed',
       'Changed priority to ' || new.priority, auth.uid(), v_email);
  end if;
  if new.deadline is distinct from old.deadline then
    insert into public.task_tracker_activity
      (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
    values
      (new.id, new.owner_id, new.title, 'deadline_changed',
       case when new.deadline is null then 'Removed deadline'
         else 'Changed deadline to '
           || to_char(new.deadline at time zone 'Asia/Manila', 'YYYY-MM-DD HH12:MI AM')
           || ' PHT'
       end, auth.uid(), v_email);
  end if;
  return new;
end;
$$;

revoke all on function public.task_tracker_log_task_change() from public, anon, authenticated;
drop trigger if exists task_tracker_log_task_change on public.task_tracker_tasks;
create trigger task_tracker_log_task_change
after insert or update or delete on public.task_tracker_tasks
for each row execute function public.task_tracker_log_task_change();

create or replace function public.task_tracker_log_subtask_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_owner_id uuid;
  v_task_title text;
  v_subtask_title text;
  v_action text;
  v_summary text;
begin
  v_task_id := case when tg_op = 'DELETE' then old.task_id else new.task_id end;
  v_owner_id := case when tg_op = 'DELETE' then old.owner_id else new.owner_id end;
  v_subtask_title := case when tg_op = 'DELETE' then old.title else new.title end;
  select t.title into v_task_title from public.task_tracker_tasks as t where t.id = v_task_id;

  if tg_op = 'INSERT' then
    v_action := 'subtask_added';
    v_summary := 'Added subtask "' || v_subtask_title || '"';
  elsif tg_op = 'DELETE' then
    v_action := 'subtask_deleted';
    v_summary := 'Removed subtask "' || v_subtask_title || '"';
  elsif new.is_completed is distinct from old.is_completed then
    v_action := 'subtask_updated';
    v_summary := case when new.is_completed then 'Completed' else 'Reopened' end
      || ' subtask "' || v_subtask_title || '"';
  elsif new.title is distinct from old.title then
    v_action := 'subtask_updated';
    v_summary := 'Renamed subtask to "' || v_subtask_title || '"';
  else
    return new;
  end if;

  insert into public.task_tracker_activity
    (task_id, owner_id, task_title, action, summary, actor_id, actor_email)
  values
    (v_task_id, v_owner_id, coalesce(v_task_title, 'Deleted task'), v_action, v_summary,
     auth.uid(), coalesce(nullif(auth.jwt() ->> 'email', ''), 'User'));

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function public.task_tracker_log_subtask_change() from public, anon, authenticated;
drop trigger if exists task_tracker_log_subtask_change on public.task_tracker_subtasks;
create trigger task_tracker_log_subtask_change
after insert or update or delete on public.task_tracker_subtasks
for each row execute function public.task_tracker_log_subtask_change();

create or replace function public.get_task_tracker_users()
returns table (id uuid, email text, created_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.is_log_admin()) then
    raise exception 'Only an admin can list Task Tracker users.';
  end if;

  return query
  select u.id, u.email::text, u.created_at
  from auth.users as u
  order by lower(coalesce(u.email, '')), u.created_at;
end;
$$;

revoke all on function public.get_task_tracker_users() from public, anon, authenticated;
grant execute on function public.get_task_tracker_users() to authenticated;

alter table public.task_tracker_tasks replica identity full;
alter table public.task_tracker_subtasks replica identity full;
alter table public.task_tracker_comments replica identity full;
alter table public.task_tracker_activity replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_tracker_tasks'
    ) then
      alter publication supabase_realtime add table public.task_tracker_tasks;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_tracker_subtasks'
    ) then
      alter publication supabase_realtime add table public.task_tracker_subtasks;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_tracker_comments'
    ) then
      alter publication supabase_realtime add table public.task_tracker_comments;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'task_tracker_activity'
    ) then
      alter publication supabase_realtime add table public.task_tracker_activity;
    end if;
  end if;
end;
$$;

notify pgrst, 'reload schema';
