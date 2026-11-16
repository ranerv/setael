create table if not exists public.activity_logs (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  action text not null check (char_length(action) <= 40),
  page text not null check (char_length(page) <= 40),
  target text not null default '' check (char_length(target) <= 100),
  device_model text not null default 'unknown' check (char_length(device_model) <= 100)
);

alter table public.activity_logs
  add column if not exists device_model text not null default 'unknown' check (char_length(device_model) <= 100);

create table if not exists public.log_admins (
  email text primary key check (email = lower(email))
);

alter table public.activity_logs enable row level security;
alter table public.log_admins enable row level security;

revoke all on public.activity_logs from anon, authenticated;
revoke all on public.log_admins from anon, authenticated;
grant insert (action, page, target, device_model) on public.activity_logs to anon, authenticated;
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
  action in ('Click', 'Login succeeded', 'Login failed', 'Opened envelope', 'Logged out')
  and page in ('index.html', 'diary.html')
  and char_length(target) <= 100
  and char_length(device_model) <= 100
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

create table if not exists public.diary_entries (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  title text not null check (char_length(title) between 1 and 120 and title = btrim(title)),
  content text not null check (char_length(content) between 1 and 20000 and content = btrim(content)),
  music_path text check (music_path is null or char_length(music_path) <= 255)
);

alter table public.diary_entries
  add column if not exists music_path text check (music_path is null or char_length(music_path) <= 255);

alter table public.diary_entries enable row level security;
revoke all on public.diary_entries from anon, authenticated;
grant select on public.diary_entries to anon, authenticated;
grant insert (title, content, music_path) on public.diary_entries to authenticated;
grant usage, select on sequence public.diary_entries_id_seq to authenticated;

drop policy if exists "Anyone can view diary envelopes" on public.diary_entries;
create policy "Anyone can view diary envelopes"
on public.diary_entries
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can add diary envelopes" on public.diary_entries;
create policy "Only the listed owner can add diary envelopes"
on public.diary_entries
for insert
to authenticated
with check ((select public.is_log_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'diary-music',
  'diary-music',
  true,
  20971520,
  array[
    'audio/mpeg',
    'audio/mp4',
    'audio/aac',
    'audio/ogg',
    'audio/wav',
    'audio/x-wav',
    'audio/webm',
    'audio/flac',
    'audio/x-m4a',
    'audio/m4a',
    'audio/opus',
    'audio/aiff',
    'audio/3gpp',
    'audio/3gpp2'
  ]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can listen to diary music" on storage.objects;
create policy "Anyone can listen to diary music"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'diary-music');

drop policy if exists "Only the listed owner can upload diary music" on storage.objects;
create policy "Only the listed owner can upload diary music"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'diary-music'
  and (select public.is_log_admin())
);

drop policy if exists "Only the listed owner can remove diary music" on storage.objects;
create policy "Only the listed owner can remove diary music"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'diary-music'
  and (select public.is_log_admin())
);

create table if not exists public.site_invitation (
  id smallint primary key default 1 check (id = 1),
  title text not null check (char_length(title) between 1 and 120 and title = btrim(title)),
  message text not null check (char_length(message) between 1 and 2000 and message = btrim(message)),
  image_path text check (
    image_path is null
    or (char_length(image_path) <= 255 and image_path = btrim(image_path))
  ),
  updated_at timestamptz not null default now()
);

alter table public.site_invitation enable row level security;
revoke all on public.site_invitation from anon, authenticated;
grant select on public.site_invitation to anon, authenticated;
grant insert, update on public.site_invitation to authenticated;

drop policy if exists "Anyone can view the site invitation" on public.site_invitation;
create policy "Anyone can view the site invitation"
on public.site_invitation
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can add the site invitation" on public.site_invitation;
create policy "Only the listed owner can add the site invitation"
on public.site_invitation
for insert
to authenticated
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can update the site invitation" on public.site_invitation;
create policy "Only the listed owner can update the site invitation"
on public.site_invitation
for update
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'invitation-photos',
  'invitation-photos',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif']
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can view invitation photos" on storage.objects;
create policy "Anyone can view invitation photos"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'invitation-photos');

drop policy if exists "Only the listed owner can upload invitation photos" on storage.objects;
create policy "Only the listed owner can upload invitation photos"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'invitation-photos'
  and (select public.is_log_admin())
);

drop policy if exists "Only the listed owner can remove invitation photos" on storage.objects;
create policy "Only the listed owner can remove invitation photos"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'invitation-photos'
  and (select public.is_log_admin())
);

-- After creating your Supabase Auth user, add its email as the only log admin:
-- insert into public.log_admins (email) values (lower('YOUR_EMAIL_ADDRESS'));

-- Owner-managed visitor site content
grant update, delete on public.diary_entries to authenticated;

alter table public.diary_entries
  add column if not exists is_published boolean not null default false;
grant insert (created_at, title, content, music_path, is_published) on public.diary_entries to authenticated;

drop policy if exists "Anyone can view diary envelopes" on public.diary_entries;
drop policy if exists "Visitors can view published diary entries" on public.diary_entries;
create policy "Visitors can view published diary entries"
on public.diary_entries
for select
to anon, authenticated
using (is_published);

drop policy if exists "Only the listed owner can view all diary entries" on public.diary_entries;
create policy "Only the listed owner can view all diary entries"
on public.diary_entries
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can edit diary envelopes" on public.diary_entries;
create policy "Only the listed owner can edit diary envelopes"
on public.diary_entries
for update
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can remove diary envelopes" on public.diary_entries;
create policy "Only the listed owner can remove diary envelopes"
on public.diary_entries
for delete
to authenticated
using ((select public.is_log_admin()));

create table if not exists public.site_settings (
  id smallint primary key default 1 check (id = 1),
  site_title text not null check (char_length(site_title) between 1 and 80 and site_title = btrim(site_title)),
  tagline text not null check (char_length(tagline) between 1 and 180 and tagline = btrim(tagline)),
  about text not null check (char_length(about) between 1 and 1000 and about = btrim(about)),
  daily_note_title text not null default '',
  daily_note_content text not null default '',
  daily_note_updated_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.site_settings
  add column if not exists daily_note_title text not null default '',
  add column if not exists daily_note_content text not null default '',
  add column if not exists daily_note_updated_at timestamptz;

insert into public.site_settings (id, site_title, tagline, about)
values (1, 'A Little Diary', 'Small moments, remembered.', 'A quiet collection of notes and photographs.')
on conflict (id) do nothing;

alter table public.site_settings enable row level security;
revoke all on public.site_settings from anon, authenticated;
grant select on public.site_settings to anon, authenticated;
grant update on public.site_settings to authenticated;

drop policy if exists "Anyone can view site settings" on public.site_settings;
create policy "Anyone can view site settings"
on public.site_settings
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can update site settings" on public.site_settings;
create policy "Only the listed owner can update site settings"
on public.site_settings
for update
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

create table if not exists public.site_photos (
  id bigint generated always as identity primary key,
  photo_path text not null unique check (char_length(photo_path) between 1 and 255),
  alt_text text not null default '' check (char_length(alt_text) <= 160),
  position integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.site_photos enable row level security;
revoke all on public.site_photos from anon, authenticated;
grant select on public.site_photos to anon, authenticated;
grant insert, update, delete on public.site_photos to authenticated;
grant usage, select on sequence public.site_photos_id_seq to authenticated;

drop policy if exists "Anyone can view published site photos" on public.site_photos;
create policy "Anyone can view published site photos"
on public.site_photos
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can add site photos" on public.site_photos;
create policy "Only the listed owner can add site photos"
on public.site_photos
for insert
to authenticated
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can edit site photos" on public.site_photos;
create policy "Only the listed owner can edit site photos"
on public.site_photos
for update
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can remove site photos" on public.site_photos;
create policy "Only the listed owner can remove site photos"
on public.site_photos
for delete
to authenticated
using ((select public.is_log_admin()));

create table if not exists public.site_daily_media (
  id bigint generated always as identity primary key,
  media_path text not null unique check (char_length(media_path) between 1 and 255),
  media_type text not null check (media_type in ('image', 'video')),
  caption text not null default '' check (char_length(caption) <= 1000),
  created_at timestamptz not null default now()
);

alter table public.site_daily_media enable row level security;
revoke all on public.site_daily_media from anon, authenticated;
grant select on public.site_daily_media to anon, authenticated;
grant insert, update, delete on public.site_daily_media to authenticated;
grant usage, select on sequence public.site_daily_media_id_seq to authenticated;

drop policy if exists "Anyone can view published daily media" on public.site_daily_media;
create policy "Anyone can view published daily media"
on public.site_daily_media
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can add daily media" on public.site_daily_media;
create policy "Only the listed owner can add daily media"
on public.site_daily_media
for insert
to authenticated
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can edit daily media" on public.site_daily_media;
create policy "Only the listed owner can edit daily media"
on public.site_daily_media
for update
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can remove daily media" on public.site_daily_media;
create policy "Only the listed owner can remove daily media"
on public.site_daily_media
for delete
to authenticated
using ((select public.is_log_admin()));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'daily-media',
  'daily-media',
  true,
  104857600,
  array[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif',
    'video/mp4', 'video/webm', 'video/quicktime'
  ]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can view daily media files" on storage.objects;
create policy "Anyone can view daily media files"
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'daily-media');

drop policy if exists "Only the listed owner can upload daily media files" on storage.objects;
create policy "Only the listed owner can upload daily media files"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'daily-media'
  and (select public.is_log_admin())
);

drop policy if exists "Only the listed owner can remove daily media files" on storage.objects;
create policy "Only the listed owner can remove daily media files"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'daily-media'
  and (select public.is_log_admin())
);

create table if not exists public.site_schedule_events (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 120 and title = btrim(title)),
  course_code text not null default '' check (char_length(course_code) <= 40),
  weekday smallint check (weekday between 1 and 6),
  event_date date,
  start_time time not null,
  end_time time not null check (end_time > start_time),
  delivery_mode text not null default 'face_to_face'
    check (delivery_mode in ('face_to_face', 'online')),
  location text not null default '' check (char_length(location) <= 120),
  seed_key text unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (
    (weekday is not null and event_date is null)
    or (weekday is null and event_date is not null)
  )
);

alter table public.site_schedule_events
  add column if not exists is_active boolean not null default true;

alter table public.site_schedule_events enable row level security;
revoke all on public.site_schedule_events from anon, authenticated;
grant select on public.site_schedule_events to anon, authenticated;
grant insert, update, delete on public.site_schedule_events to authenticated;
grant usage, select on sequence public.site_schedule_events_id_seq to authenticated;

drop policy if exists "Anyone can view the class schedule" on public.site_schedule_events;
create policy "Anyone can view the class schedule"
on public.site_schedule_events
for select
to anon, authenticated
using (true);

drop policy if exists "Only the listed owner can manage the class schedule" on public.site_schedule_events;
create policy "Only the listed owner can manage the class schedule"
on public.site_schedule_events
for all
to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

create index if not exists site_schedule_events_weekly_idx
  on public.site_schedule_events (weekday, start_time)
  where is_active and weekday is not null;
create index if not exists site_schedule_events_dated_idx
  on public.site_schedule_events (event_date, start_time)
  where is_active and event_date is not null;

insert into public.site_schedule_events
  (title, course_code, weekday, event_date, start_time, end_time, delivery_mode, location, seed_key)
values
  ('ABE 616 Lab', '', 1, null, '09:30', '10:30', 'face_to_face', 'AD 401', 'class-mon-abe616'),
  ('ABE 618 Lab', '', 1, null, '10:30', '12:00', 'face_to_face', 'AD 401', 'class-mon-abe618'),
  ('GEC 606', '', 1, null, '13:00', '14:30', 'face_to_face', 'AD 401', 'class-mon-gec606'),
  ('ABE 613 Lec', '', 1, null, '14:30', '15:30', 'face_to_face', 'AD 401', 'class-mon-abe613'),
  ('ABE 614 Lec', '', 1, null, '15:30', '16:30', 'face_to_face', 'AD 401', 'class-mon-abe614-lec'),
  ('ABE 614 Lab', '', 1, null, '16:30', '18:00', 'face_to_face', 'AD 401', 'class-mon-abe614-lab'),
  ('GEC 603', '', 2, null, '09:30', '10:30', 'face_to_face', 'AD 401', 'class-tue-gec603'),
  ('ABE 618 Lab', '', 2, null, '10:30', '12:00', 'face_to_face', 'AD 401', 'class-tue-abe618'),
  ('2-ABE Course', '', 2, null, '13:30', '14:30', 'face_to_face', 'AD 401', 'class-tue-2abe'),
  ('ABE 615 Lec', '', 2, null, '14:30', '15:30', 'face_to_face', 'AD 401', 'class-tue-abe615-lec'),
  ('ABE 616 Lec', '', 2, null, '15:30', '16:30', 'face_to_face', 'AD 401', 'class-tue-abe616'),
  ('ABE 616 Lab', '', 3, null, '09:30', '10:30', 'face_to_face', 'AD 401', 'class-wed-abe616'),
  ('ABE 618 Lab', '', 3, null, '10:30', '12:00', 'face_to_face', 'AD 401', 'class-wed-abe618'),
  ('GEC 606', '', 3, null, '13:00', '14:30', 'face_to_face', 'AD 401', 'class-wed-gec606'),
  ('ABE 613 Lec', '', 3, null, '14:30', '15:30', 'face_to_face', 'AD 401', 'class-wed-abe613'),
  ('ABE 614 Lec', '', 3, null, '15:30', '16:30', 'face_to_face', 'AD 401', 'class-wed-abe614-lec'),
  ('ABE 614 Lab', '', 3, null, '17:00', '18:00', 'face_to_face', 'AD 401', 'class-wed-abe614-lab'),
  ('GEC 603', '', 4, null, '09:30', '10:30', 'face_to_face', 'AD 401', 'class-thu-gec603'),
  ('ABE 615 Lab', '', 4, null, '10:30', '12:00', 'face_to_face', 'AD 401', 'class-thu-abe615'),
  ('2-ABE Course', '', 4, null, '13:30', '14:30', 'face_to_face', 'AD 401', 'class-thu-2abe'),
  ('ABE 615 Lec', '', 4, null, '14:30', '15:30', 'face_to_face', 'AD 401', 'class-thu-abe615-lec'),
  ('ABE 616 Lec', '', 4, null, '15:30', '16:30', 'face_to_face', 'AD 401', 'class-thu-abe616'),
  ('ABE 615 Seminar', '', 5, null, '09:30', '12:00', 'face_to_face', 'AD 401', 'class-fri-abe615'),
  ('ABE 612 Lab', '', 5, null, '13:30', '16:30', 'face_to_face', 'AD 401', 'class-fri-abe612'),
  ('ABE 617', '', 5, null, '16:30', '17:30', 'face_to_face', 'AD 401', 'class-fri-abe617')
on conflict (seed_key) do nothing;

create table if not exists public.site_chat_threads (
  id bigint generated always as identity primary key,
  visitor_token uuid not null unique,
  display_name text not null default 'Visitor'
    check (char_length(display_name) between 1 and 60),
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table if not exists public.site_chat_messages (
  id bigint generated always as identity primary key,
  thread_id bigint not null references public.site_chat_threads(id) on delete cascade,
  sender text not null check (sender in ('visitor', 'owner')),
  sender_label text not null default 'Visitor' check (char_length(sender_label) <= 60),
  message text not null check (char_length(message) between 1 and 2000 and message = btrim(message)),
  created_at timestamptz not null default now()
);

create index if not exists site_chat_threads_last_message_idx
  on public.site_chat_threads (last_message_at desc);
create index if not exists site_chat_messages_thread_id_idx
  on public.site_chat_messages (thread_id, id);

alter table public.site_chat_threads enable row level security;
alter table public.site_chat_messages enable row level security;
revoke all on public.site_chat_threads from anon, authenticated;
revoke all on public.site_chat_messages from anon, authenticated;
grant select, delete on public.site_chat_threads to authenticated;
grant select, insert on public.site_chat_messages to authenticated;
grant usage, select on sequence public.site_chat_messages_id_seq to authenticated;

drop policy if exists "Only the listed owner can view chat threads" on public.site_chat_threads;
create policy "Only the listed owner can view chat threads"
on public.site_chat_threads
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can remove chat threads" on public.site_chat_threads;
create policy "Only the listed owner can remove chat threads"
on public.site_chat_threads
for delete
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can view chat messages" on public.site_chat_messages;
create policy "Only the listed owner can view chat messages"
on public.site_chat_messages
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can reply in chat" on public.site_chat_messages;
create policy "Only the listed owner can reply in chat"
on public.site_chat_messages
for insert
to authenticated
with check (
  sender = 'owner'
  and sender_label = 'Owner'
  and (select public.is_log_admin())
);

create or replace function public.touch_site_chat_thread()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.site_chat_threads
  set last_message_at = new.created_at
  where id = new.thread_id;
  return new;
end;
$$;

drop trigger if exists site_chat_message_updates_thread on public.site_chat_messages;
create trigger site_chat_message_updates_thread
after insert on public.site_chat_messages
for each row execute function public.touch_site_chat_thread();

create or replace function public.get_visitor_chat_messages(p_visitor_token uuid)
returns table (id bigint, sender text, sender_label text, message text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.sender, m.sender_label, m.message, m.created_at
  from public.site_chat_threads t
  join public.site_chat_messages m on m.thread_id = t.id
  where t.visitor_token = p_visitor_token
  order by m.id;
$$;

create or replace function public.send_visitor_chat_message(
  p_visitor_token uuid,
  p_display_name text,
  p_message text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thread_id bigint;
  v_last_visitor_message timestamptz;
  v_message_id bigint;
  v_display_name text;
  v_message text;
begin
  if p_visitor_token is null then
    raise exception 'A chat session is required.';
  end if;

  v_display_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  if char_length(v_display_name) > 60 then
    raise exception 'Names must be 60 characters or fewer.';
  end if;

  v_message := btrim(p_message);
  if v_message is null or char_length(v_message) not between 1 and 2000 then
    raise exception 'Messages must be between 1 and 2,000 characters.';
  end if;

  insert into public.site_chat_threads (visitor_token, display_name)
  values (p_visitor_token, v_display_name)
  on conflict (visitor_token) do update
  set display_name = excluded.display_name
  returning id into v_thread_id;

  select created_at into v_last_visitor_message
  from public.site_chat_messages
  where thread_id = v_thread_id and sender = 'visitor'
  order by id desc
  limit 1;

  if v_last_visitor_message > now() - interval '3 seconds' then
    raise exception 'Please wait a moment before sending another message.';
  end if;

  insert into public.site_chat_messages (thread_id, sender, sender_label, message)
  values (v_thread_id, 'visitor', v_display_name, v_message)
  returning id into v_message_id;

  return v_message_id;
end;
$$;

revoke all on function public.touch_site_chat_thread() from public;
revoke all on function public.get_visitor_chat_messages(uuid) from public, anon, authenticated;
revoke all on function public.send_visitor_chat_message(uuid, text, text) from public, anon, authenticated;

create table if not exists public.visitor_threads (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  display_name text not null default 'Visitor'
    check (char_length(display_name) between 1 and 60),
  content text not null default ''
    check (char_length(content) <= 2000),
  image_path text
    check (image_path is null or char_length(image_path) <= 255),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (char_length(btrim(content)) > 0 or image_path is not null)
);

create table if not exists public.visitor_thread_comments (
  id bigint generated always as identity primary key,
  thread_id bigint not null references public.visitor_threads(id) on delete cascade,
  visitor_token uuid,
  sender text not null check (sender in ('visitor', 'owner')),
  sender_label text not null default 'Visitor'
    check (char_length(sender_label) between 1 and 60),
  content text not null
    check (char_length(content) between 1 and 1000 and content = btrim(content)),
  created_at timestamptz not null default now(),
  check (
    (sender = 'visitor' and visitor_token is not null)
    or (sender = 'owner' and visitor_token is null)
  )
);

create index if not exists visitor_threads_token_created_idx
  on public.visitor_threads (visitor_token, created_at desc);
create index if not exists visitor_thread_comments_thread_created_idx
  on public.visitor_thread_comments (thread_id, created_at);

alter table public.visitor_threads enable row level security;
alter table public.visitor_thread_comments enable row level security;
revoke all on public.visitor_threads from anon, authenticated;
revoke all on public.visitor_thread_comments from anon, authenticated;
grant select on public.visitor_threads to authenticated;
grant select, insert on public.visitor_thread_comments to authenticated;
grant usage, select on sequence public.visitor_threads_id_seq to authenticated;
grant usage, select on sequence public.visitor_thread_comments_id_seq to authenticated;

drop policy if exists "Only the listed owner can view visitor threads" on public.visitor_threads;
create policy "Only the listed owner can view visitor threads"
on public.visitor_threads
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can view visitor thread comments" on public.visitor_thread_comments;
create policy "Only the listed owner can view visitor thread comments"
on public.visitor_thread_comments
for select
to authenticated
using ((select public.is_log_admin()));

drop policy if exists "Only the listed owner can comment on visitor threads" on public.visitor_thread_comments;
create policy "Only the listed owner can comment on visitor threads"
on public.visitor_thread_comments
for insert
to authenticated
with check (
  sender = 'owner'
  and sender_label = 'Owner'
  and visitor_token is null
  and (select public.is_log_admin())
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'visitor-thread-images',
  'visitor-thread-images',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif']
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Visitors can upload thread photos" on storage.objects;
create policy "Visitors can upload thread photos"
on storage.objects
for insert
to anon, authenticated
with check (
  bucket_id = 'visitor-thread-images'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);

create or replace function public.get_visitor_threads(p_visitor_token uuid)
returns table (
  id bigint,
  display_name text,
  content text,
  image_path text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.display_name, t.content, t.image_path, t.created_at, t.updated_at
  from public.visitor_threads t
  where t.visitor_token = p_visitor_token
  order by t.created_at desc, t.id desc;
$$;

create or replace function public.get_visitor_thread_comments(
  p_visitor_token uuid,
  p_thread_id bigint
)
returns table (
  id bigint,
  sender text,
  sender_label text,
  content text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.sender, c.sender_label, c.content, c.created_at
  from public.visitor_threads t
  join public.visitor_thread_comments c on c.thread_id = t.id
  where t.id = p_thread_id
    and t.visitor_token = p_visitor_token
  order by c.created_at, c.id;
$$;

create or replace function public.create_visitor_thread(
  p_visitor_token uuid,
  p_display_name text,
  p_content text,
  p_image_path text
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
begin
  if p_visitor_token is null then
    raise exception 'A private thread session is required.';
  end if;

  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then
    raise exception 'Names must be 60 characters or fewer.';
  end if;
  if char_length(v_content) > 2000 then
    raise exception 'Threads must be 2,000 characters or fewer.';
  end if;
  if v_content = '' and p_image_path is null then
    raise exception 'Write something or add a photo before posting.';
  end if;
  if p_image_path is not null and (
    char_length(p_image_path) > 255
    or split_part(p_image_path, '/', 1) <> p_visitor_token::text
    or split_part(p_image_path, '/', 2) = ''
    or split_part(p_image_path, '/', 3) <> ''
  ) then
    raise exception 'The photo does not belong to this private thread session.';
  end if;
  if p_image_path is not null and not exists (
    select 1 from storage.objects
    where bucket_id = 'visitor-thread-images' and name = p_image_path
  ) then
    raise exception 'The uploaded photo could not be found.';
  end if;

  insert into public.visitor_threads (visitor_token, display_name, content, image_path)
  values (p_visitor_token, v_name, v_content, p_image_path)
  returning id into v_thread_id;
  return v_thread_id;
end;
$$;

create or replace function public.update_visitor_thread(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text,
  p_image_path text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_content text;
begin
  if p_visitor_token is null then
    raise exception 'A private thread session is required.';
  end if;

  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then
    raise exception 'Names must be 60 characters or fewer.';
  end if;
  if char_length(v_content) > 2000 then
    raise exception 'Threads must be 2,000 characters or fewer.';
  end if;
  if v_content = '' and p_image_path is null then
    raise exception 'Write something or keep a photo before saving.';
  end if;
  if p_image_path is not null and (
    char_length(p_image_path) > 255
    or split_part(p_image_path, '/', 1) <> p_visitor_token::text
    or split_part(p_image_path, '/', 2) = ''
    or split_part(p_image_path, '/', 3) <> ''
  ) then
    raise exception 'The photo does not belong to this private thread session.';
  end if;
  if p_image_path is not null and not exists (
    select 1 from storage.objects
    where bucket_id = 'visitor-thread-images' and name = p_image_path
  ) then
    raise exception 'The uploaded photo could not be found.';
  end if;

  update public.visitor_threads
  set display_name = v_name,
      content = v_content,
      image_path = p_image_path,
      updated_at = now()
  where id = p_thread_id and visitor_token = p_visitor_token;
  if not found then
    raise exception 'This thread could not be found for this browser.';
  end if;
  return true;
end;
$$;

create or replace function public.delete_visitor_thread(
  p_visitor_token uuid,
  p_thread_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.visitor_threads
  where id = p_thread_id and visitor_token = p_visitor_token;
  if not found then
    raise exception 'This thread could not be found for this browser.';
  end if;
  return true;
end;
$$;

create or replace function public.add_visitor_thread_comment(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content text;
  v_name text;
  v_last_comment timestamptz;
  v_comment_id bigint;
begin
  if p_visitor_token is null or not exists (
    select 1 from public.visitor_threads
    where id = p_thread_id and visitor_token = p_visitor_token
  ) then
    raise exception 'This thread could not be found for this browser.';
  end if;

  v_content := btrim(coalesce(p_content, ''));
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  if char_length(v_content) not between 1 and 1000 then
    raise exception 'Comments must be between 1 and 1,000 characters.';
  end if;
  if char_length(v_name) > 60 then
    raise exception 'Names must be 60 characters or fewer.';
  end if;

  select max(created_at) into v_last_comment
  from public.visitor_thread_comments
  where thread_id = p_thread_id and visitor_token = p_visitor_token;
  if v_last_comment > now() - interval '3 seconds' then
    raise exception 'Please wait a moment before commenting again.';
  end if;

  insert into public.visitor_thread_comments (thread_id, visitor_token, sender, sender_label, content)
  values (p_thread_id, p_visitor_token, 'visitor', v_name, v_content)
  returning id into v_comment_id;
  return v_comment_id;
end;
$$;

revoke all on function public.get_visitor_threads(uuid) from public, anon, authenticated;
revoke all on function public.get_visitor_thread_comments(uuid, bigint) from public, anon, authenticated;
revoke all on function public.create_visitor_thread(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.update_visitor_thread(uuid, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.delete_visitor_thread(uuid, bigint) from public, anon, authenticated;
revoke all on function public.add_visitor_thread_comment(uuid, bigint, text, text) from public, anon, authenticated;
grant execute on function public.get_visitor_threads(uuid) to anon, authenticated;
grant execute on function public.get_visitor_thread_comments(uuid, bigint) to anon, authenticated;
grant execute on function public.create_visitor_thread(uuid, text, text, text) to anon, authenticated;
grant execute on function public.update_visitor_thread(uuid, bigint, text, text, text) to anon, authenticated;
grant execute on function public.delete_visitor_thread(uuid, bigint) to anon, authenticated;
grant execute on function public.add_visitor_thread_comment(uuid, bigint, text, text) to anon, authenticated;

alter database postgres set timezone to 'Asia/Manila';

notify pgrst, 'reload schema';
