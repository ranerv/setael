-- Admin-only chat read receipts

create table if not exists public.group_chat_read_receipts (
  message_id bigint not null references public.group_chat_messages(id) on delete cascade,
  visitor_token uuid not null,
  visitor_name text,
  read_at timestamptz not null default now(),
  primary key (message_id, visitor_token)
);

alter table public.group_chat_read_receipts
  add column if not exists visitor_name text;

alter table public.group_chat_read_receipts
  drop constraint if exists group_chat_read_receipts_visitor_name_check;
alter table public.group_chat_read_receipts
  add constraint group_chat_read_receipts_visitor_name_check
  check (visitor_name is null or char_length(btrim(visitor_name)) between 1 and 60);

alter table public.group_chat_read_receipts enable row level security;
revoke all on public.group_chat_read_receipts from public, anon, authenticated;

drop function if exists public.mark_group_chat_seen(uuid, bigint[]);
drop function if exists public.mark_group_chat_seen(uuid, bigint[], text);
create or replace function public.mark_group_chat_seen(
  p_visitor_token uuid,
  p_message_ids bigint[],
  p_display_name text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_display_name text;
begin
  if p_visitor_token is null then
    raise exception 'A chat session is required.';
  end if;

  v_display_name := nullif(btrim(p_display_name), '');
  if lower(v_display_name) = 'visitor' then
    v_display_name := null;
  end if;
  if char_length(v_display_name) > 60 then
    raise exception 'Name must be 60 characters or fewer.';
  end if;

  insert into public.group_chat_read_receipts as existing_receipt (
    message_id,
    visitor_token,
    visitor_name
  )
  select
    m.id,
    p_visitor_token,
    v_display_name
  from public.group_chat_messages m
  where m.id = any(coalesce(p_message_ids, array[]::bigint[]))
    and m.is_owner
    and not m.is_deleted
    and m.visitor_token <> p_visitor_token
  on conflict (message_id, visitor_token) do update
  set visitor_name = coalesce(excluded.visitor_name, existing_receipt.visitor_name);
end;
$$;

drop function if exists public.get_group_chat_seen_counts();
create or replace function public.get_group_chat_seen_counts()
returns table (
  message_id bigint,
  reader_count bigint,
  visitor_receipts jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.is_log_admin()) then
    raise exception 'Only the owner can view chat read receipts.';
  end if;

  return query
  select
    r.message_id,
    count(*)::bigint,
    jsonb_agg(
      jsonb_build_object(
        'name', coalesce(
          nullif(btrim(r.visitor_name), ''),
          'Visitor ' || upper(right(r.visitor_token::text, 4))
        ),
        'read_at', r.read_at
      )
      order by r.read_at, r.visitor_token
    )
  from public.group_chat_read_receipts r
  group by r.message_id;
end;
$$;

revoke all on function public.mark_group_chat_seen(uuid, bigint[], text)
  from public, anon, authenticated;
revoke all on function public.get_group_chat_seen_counts()
  from public, anon, authenticated;

grant execute on function public.mark_group_chat_seen(uuid, bigint[], text)
  to anon, authenticated;
grant execute on function public.get_group_chat_seen_counts()
  to authenticated;

notify pgrst, 'reload schema';
