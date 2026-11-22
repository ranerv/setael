create or replace function public.get_group_chat_messages_page(
  p_before_created_at timestamptz default null,
  p_before_id bigint default null,
  p_limit integer default 100
)
returns table (
  id bigint,
  visitor_token uuid,
  display_name text,
  is_owner boolean,
  message text,
  media_path text,
  media_type text,
  reply_to_id bigint,
  reply_preview text,
  reply_author text,
  is_deleted boolean,
  created_at timestamptz,
  updated_at timestamptz
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

revoke all on function public.get_group_chat_messages_page(timestamptz, bigint, integer)
  from public, anon, authenticated;
grant execute on function public.get_group_chat_messages_page(timestamptz, bigint, integer)
  to anon, authenticated;

notify pgrst, 'reload schema';
