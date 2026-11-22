-- Requires the existing group_chat_messages, visitor_threads, and is_log_admin() setup.

create or replace function public.get_group_chat_messages()
returns table (
  id bigint, visitor_token uuid, display_name text, is_owner boolean,
  message text, media_path text, media_type text,
  reply_to_id bigint, reply_preview text, reply_author text,
  is_deleted boolean, created_at timestamptz, updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select id, visitor_token, display_name, is_owner, message, media_path, media_type,
         reply_to_id, reply_preview, reply_author, is_deleted, created_at, updated_at
  from public.group_chat_messages
  order by created_at, id;
$$;

create or replace function public.get_group_chat_messages_page(
  p_before_created_at timestamptz default null,
  p_before_id bigint default null,
  p_limit integer default 100
)
returns table (
  id bigint, visitor_token uuid, display_name text, is_owner boolean,
  message text, media_path text, media_type text,
  reply_to_id bigint, reply_preview text, reply_author text,
  is_deleted boolean, created_at timestamptz, updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 100);
begin
  if (p_before_created_at is null) <> (p_before_id is null) then
    raise exception 'Both history cursor values must be provided together.';
  end if;

  return query
  select page.id, page.visitor_token, page.display_name, page.is_owner,
         page.message, page.media_path, page.media_type, page.reply_to_id,
         page.reply_preview, page.reply_author, page.is_deleted,
         page.created_at, page.updated_at
  from (
    select m.id, m.visitor_token, m.display_name, m.is_owner,
           m.message, m.media_path, m.media_type, m.reply_to_id,
           m.reply_preview, m.reply_author, m.is_deleted,
           m.created_at, m.updated_at
    from public.group_chat_messages m
    where p_before_created_at is null
      or (m.created_at, m.id) < (p_before_created_at, p_before_id)
    order by m.created_at desc, m.id desc
    limit v_limit
  ) as page
  order by page.created_at, page.id;
end;
$$;

alter table public.visitor_threads
  add column if not exists media_items jsonb not null default '[]'::jsonb;

alter table public.visitor_threads
  drop constraint if exists visitor_threads_media_items_check;
alter table public.visitor_threads
  add constraint visitor_threads_media_items_check
  check (jsonb_typeof(media_items) = 'array');
alter table public.visitor_threads
  drop constraint if exists visitor_threads_check;
alter table public.visitor_threads
  drop constraint if exists visitor_threads_media_presence_check;
alter table public.visitor_threads
  add constraint visitor_threads_media_presence_check
  check (
    char_length(btrim(content)) > 0
    or image_path is not null
    or media_path is not null
    or jsonb_array_length(media_items) > 0
  );

create or replace function public.validate_thread_media_items(p_items jsonb, p_expected_folder text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_path text;
  v_type text;
  v_caption text;
begin
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' then
    raise exception 'Media attachments must be a list.';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 10 then
    raise exception 'A thread can have up to 10 photos or videos.';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) as items(value)
  loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'Invalid media attachment.';
    end if;
    v_path := v_item->>'path';
    v_type := v_item->>'type';
    v_caption := coalesce(v_item->>'caption', '');
    if v_path is null or char_length(v_path) > 255
      or split_part(v_path, '/', 1) <> p_expected_folder then
      raise exception 'A media file does not belong to this session.';
    end if;
    if v_type is null or v_type not in ('image', 'video') then
      raise exception 'Invalid media type.';
    end if;
    if char_length(v_caption) > 500 then
      raise exception 'Media captions must be 500 characters or fewer.';
    end if;
    if not exists (
      select 1 from storage.objects
      where bucket_id = 'visitor-thread-images' and name = v_path
    ) then
      raise exception 'An uploaded media file could not be found.';
    end if;
  end loop;
end;
$$;

revoke all on function public.validate_thread_media_items(jsonb, text) from public, anon, authenticated;

create or replace function public.create_visitor_thread_with_media(
  p_visitor_token uuid,
  p_display_name text,
  p_content text,
  p_media_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_content text;
  v_thread_id bigint;
  v_items jsonb := coalesce(p_media_items, '[]'::jsonb);
begin
  if p_visitor_token is null then raise exception 'A private thread session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if char_length(v_content) > 2000 then raise exception 'Threads must be 2,000 characters or fewer.'; end if;
  if v_content = '' and jsonb_array_length(v_items) = 0 then
    raise exception 'Write something or add a photo or video before posting.';
  end if;
  perform public.validate_thread_media_items(v_items, p_visitor_token::text);
  insert into public.visitor_threads (visitor_token, display_name, content, media_items)
  values (p_visitor_token, v_name, v_content, v_items)
  returning id into v_thread_id;
  return v_thread_id;
end;
$$;

create or replace function public.update_visitor_thread_with_media(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text,
  p_media_items jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_content text;
  v_items jsonb := coalesce(p_media_items, '[]'::jsonb);
begin
  if p_visitor_token is null then raise exception 'A private thread session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if char_length(v_content) > 2000 then raise exception 'Threads must be 2,000 characters or fewer.'; end if;
  if v_content = '' and jsonb_array_length(v_items) = 0 then
    raise exception 'Write something or keep a photo or video before saving.';
  end if;
  perform public.validate_thread_media_items(v_items, p_visitor_token::text);
  update public.visitor_threads
  set display_name = v_name, content = v_content,
      image_path = null, media_path = null, media_type = null,
      media_items = v_items, updated_at = now()
  where id = p_thread_id and visitor_token = p_visitor_token;
  if not found then raise exception 'This thread could not be found for this browser.'; end if;
  return true;
end;
$$;

create or replace function public.create_owner_thread_with_media(
  p_display_name text,
  p_content text,
  p_media_items jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content text := btrim(coalesce(p_content, ''));
  v_items jsonb := coalesce(p_media_items, '[]'::jsonb);
  v_thread_id bigint;
begin
  if not (select public.is_log_admin()) then
    raise exception 'Only the owner can post owner threads.';
  end if;
  if char_length(v_content) > 2000 then raise exception 'Threads must be 2,000 characters or fewer.'; end if;
  if v_content = '' and jsonb_array_length(v_items) = 0 then
    raise exception 'Write something or add media before posting.';
  end if;
  perform public.validate_thread_media_items(v_items, 'owner');
  insert into public.visitor_threads (
    visitor_token, display_name, content, media_items, is_owner_post
  )
  values (
    '00000000-0000-0000-0000-000000000000'::uuid,
    coalesce(nullif(btrim(p_display_name), ''), 'Vren'),
    v_content, v_items, true
  )
  returning id into v_thread_id;
  return v_thread_id;
end;
$$;

drop function if exists public.get_all_visitor_threads();
create function public.get_all_visitor_threads()
returns table (
  id bigint,
  visitor_token uuid,
  display_name text,
  content text,
  image_path text,
  media_path text,
  media_type text,
  is_owner_post boolean,
  created_at timestamptz,
  updated_at timestamptz,
  media_items jsonb
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.visitor_token, t.display_name, t.content,
         t.image_path, t.media_path, t.media_type, t.is_owner_post,
         t.created_at, t.updated_at, t.media_items
  from public.visitor_threads t
  order by t.created_at desc, t.id desc;
$$;

revoke all on function public.create_visitor_thread_with_media(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.update_visitor_thread_with_media(uuid, bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.create_owner_thread_with_media(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.get_all_visitor_threads() from public, anon, authenticated;
grant execute on function public.create_visitor_thread_with_media(uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.update_visitor_thread_with_media(uuid, bigint, text, text, jsonb) to anon, authenticated;
grant execute on function public.create_owner_thread_with_media(text, text, jsonb) to authenticated;
grant execute on function public.get_all_visitor_threads() to anon, authenticated;

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
create function public.mark_group_chat_seen(
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
  if lower(v_display_name) = 'visitor' then v_display_name := null; end if;
  if char_length(v_display_name) > 60 then
    raise exception 'Name must be 60 characters or fewer.';
  end if;

  insert into public.group_chat_read_receipts as existing_receipt (
    message_id, visitor_token, visitor_name
  )
  select m.id, p_visitor_token, v_display_name
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
create function public.get_group_chat_seen_counts()
returns table (message_id bigint, reader_count bigint, visitor_receipts jsonb)
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

revoke all on function public.validate_thread_media_items(jsonb, text) from public, anon, authenticated;
revoke all on function public.create_visitor_thread_with_media(uuid, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.update_visitor_thread_with_media(uuid, bigint, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.create_owner_thread_with_media(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.get_all_visitor_threads() from public, anon, authenticated;
revoke all on function public.mark_group_chat_seen(uuid, bigint[], text) from public, anon, authenticated;
revoke all on function public.get_group_chat_seen_counts() from public, anon, authenticated;
revoke all on function public.get_group_chat_messages_page(timestamptz, bigint, integer) from public, anon, authenticated;
grant execute on function public.create_visitor_thread_with_media(uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.update_visitor_thread_with_media(uuid, bigint, text, text, jsonb) to anon, authenticated;
grant execute on function public.create_owner_thread_with_media(text, text, jsonb) to authenticated;
grant execute on function public.get_all_visitor_threads() to anon, authenticated;
grant execute on function public.mark_group_chat_seen(uuid, bigint[], text) to anon, authenticated;
grant execute on function public.get_group_chat_seen_counts() to authenticated;
grant execute on function public.get_group_chat_messages_page(timestamptz, bigint, integer) to anon, authenticated;

notify pgrst, 'reload schema';
