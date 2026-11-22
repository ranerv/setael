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
  action in ('Click', 'Login succeeded', 'Login failed', 'Opened envelope', 'Logged out', 'Reminder added', 'Reminder updated', 'Liked note', 'Liked photo', 'Liked video', 'Check-in sent')
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

create table if not exists public.visitor_content_likes (
  content_type text not null check (content_type in ('daily_note', 'daily_media')),
  content_id text not null check (char_length(content_id) between 1 and 20),
  visitor_token uuid not null,
  created_at timestamptz not null default now(),
  primary key (content_type, content_id, visitor_token)
);

alter table public.visitor_content_likes enable row level security;
revoke all on public.visitor_content_likes from anon, authenticated;

create or replace function public.get_daily_content_like_status(
  p_visitor_token uuid,
  p_content_type text,
  p_content_id text
)
returns table (like_count bigint, liked boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_valid boolean := false;
begin
  if p_visitor_token is null then
    raise exception 'A visitor session is required.';
  end if;
  if p_content_type = 'daily_note' and p_content_id ~ '^[0-9]{1,16}$' then
    select exists (
      select 1
      from public.site_settings s
      where s.id = 1
        and char_length(btrim(s.daily_note_title)) > 0
        and char_length(btrim(s.daily_note_content)) > 0
        and s.daily_note_updated_at is not null
        and floor(extract(epoch from s.daily_note_updated_at) * 1000)::bigint = p_content_id::bigint
        and s.daily_note_updated_at <= now()
        and s.daily_note_updated_at > now() - interval '24 hours'
    ) into v_valid;
  elsif p_content_type = 'daily_media' and p_content_id ~ '^[0-9]{1,20}$' then
    select exists (
      select 1
      from public.site_daily_media m
      where m.id::text = p_content_id
        and m.created_at <= now()
        and m.created_at > now() - interval '24 hours'
        and m.id = (
          select newest.id
          from public.site_daily_media newest
          order by newest.created_at desc, newest.id desc
          limit 1
        )
    ) into v_valid;
  end if;
  if not v_valid then
    raise exception 'This daily item is no longer available to like.';
  end if;

  return query
  select count(*), exists (
    select 1
    from public.visitor_content_likes l
    where l.content_type = p_content_type
      and l.content_id = p_content_id
      and l.visitor_token = p_visitor_token
  )
  from public.visitor_content_likes l
  where l.content_type = p_content_type
    and l.content_id = p_content_id;
end;
$$;

create or replace function public.toggle_daily_content_like(
  p_visitor_token uuid,
  p_content_type text,
  p_content_id text
)
returns table (like_count bigint, liked boolean)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_valid boolean := false;
  v_deleted integer;
begin
  if p_visitor_token is null then
    raise exception 'A visitor session is required.';
  end if;
  if p_content_type = 'daily_note' and p_content_id ~ '^[0-9]{1,16}$' then
    select exists (
      select 1
      from public.site_settings s
      where s.id = 1
        and char_length(btrim(s.daily_note_title)) > 0
        and char_length(btrim(s.daily_note_content)) > 0
        and s.daily_note_updated_at is not null
        and floor(extract(epoch from s.daily_note_updated_at) * 1000)::bigint = p_content_id::bigint
        and s.daily_note_updated_at <= now()
        and s.daily_note_updated_at > now() - interval '24 hours'
    ) into v_valid;
  elsif p_content_type = 'daily_media' and p_content_id ~ '^[0-9]{1,20}$' then
    select exists (
      select 1
      from public.site_daily_media m
      where m.id::text = p_content_id
        and m.created_at <= now()
        and m.created_at > now() - interval '24 hours'
        and m.id = (
          select newest.id
          from public.site_daily_media newest
          order by newest.created_at desc, newest.id desc
          limit 1
        )
    ) into v_valid;
  end if;
  if not v_valid then
    raise exception 'This daily item is no longer available to like.';
  end if;

  delete from public.visitor_content_likes l
  where l.content_type = p_content_type
    and l.content_id = p_content_id
    and l.visitor_token = p_visitor_token;
  get diagnostics v_deleted = row_count;
  if v_deleted = 0 then
    insert into public.visitor_content_likes (content_type, content_id, visitor_token)
    values (p_content_type, p_content_id, p_visitor_token)
    on conflict (content_type, content_id, visitor_token) do nothing;
  end if;

  return query
  select count(*), exists (
    select 1
    from public.visitor_content_likes l
    where l.content_type = p_content_type
      and l.content_id = p_content_id
      and l.visitor_token = p_visitor_token
  )
  from public.visitor_content_likes l
  where l.content_type = p_content_type
    and l.content_id = p_content_id;
end;
$$;

revoke all on function public.get_daily_content_like_status(uuid, text, text) from public, anon, authenticated;
revoke all on function public.toggle_daily_content_like(uuid, text, text) from public, anon, authenticated;
grant execute on function public.get_daily_content_like_status(uuid, text, text) to anon, authenticated;
grant execute on function public.toggle_daily_content_like(uuid, text, text) to anon, authenticated;

create table if not exists public.visitor_checkins (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  answer text not null check (answer in ('yes', 'no')),
  message text not null default '' check (char_length(message) <= 1000),
  created_at timestamptz not null default now(),
  check (answer = 'yes' or message = '')
);

create index if not exists visitor_checkins_created_idx
  on public.visitor_checkins (created_at desc, id desc);

alter table public.visitor_checkins enable row level security;
revoke all on public.visitor_checkins from anon, authenticated;
grant select on public.visitor_checkins to authenticated;

drop policy if exists "Only the listed owner can view visitor check-ins" on public.visitor_checkins;
create policy "Only the listed owner can view visitor check-ins"
on public.visitor_checkins
for select
to authenticated
using ((select public.is_log_admin()));

create or replace function public.submit_visitor_checkin(
  p_visitor_token uuid,
  p_answer text,
  p_message text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_message text := btrim(coalesce(p_message, ''));
  v_id bigint;
begin
  if p_visitor_token is null or p_answer is null or p_answer not in ('yes', 'no') then
    raise exception 'Choose a yes or no response.';
  end if;
  if char_length(v_message) > 1000 then
    raise exception 'Your message must be 1,000 characters or fewer.';
  end if;
  if p_answer = 'no' and v_message <> '' then
    raise exception 'A follow-up message is only available with a yes response.';
  end if;

  insert into public.visitor_checkins (visitor_token, answer, message)
  values (p_visitor_token, p_answer, v_message)
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.submit_visitor_checkin(uuid, text, text) from public, anon, authenticated;
grant execute on function public.submit_visitor_checkin(uuid, text, text) to anon, authenticated;

alter database postgres set timezone to 'Asia/Manila';

notify pgrst, 'reload schema';

-- ── Re-apply activity_logs insert policy with expanded allowed actions ───────
-- Run this block after updating to add like and check-in logging support.
drop policy if exists "Visitors can submit limited activity" on public.activity_logs;
create policy "Visitors can submit limited activity"
on public.activity_logs
for insert
to anon, authenticated
with check (
  action in (
    'Click', 'Login succeeded', 'Login failed', 'Opened envelope', 'Logged out',
    'Reminder added', 'Reminder updated',
    'Liked note', 'Liked photo', 'Liked video',
    'Check-in sent'
  )
  and page in ('index.html', 'diary.html')
  and char_length(target) <= 100
  and char_length(device_model) <= 100
);

notify pgrst, 'reload schema';

-- ── Public threads: all visitors see all threads & comments ──────────────────

-- 1. Return ALL threads (not filtered by token) so every visitor sees everyone's posts
drop function if exists public.get_all_visitor_threads();
create or replace function public.get_all_visitor_threads()
returns table (
  id bigint,
  visitor_token uuid,
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
  select t.id, t.visitor_token, t.display_name, t.content, t.image_path,
         t.created_at, t.updated_at
  from public.visitor_threads t
  order by t.created_at desc, t.id desc;
$$;

-- 2. Return ALL comments for a thread (not filtered by token)
drop function if exists public.get_all_thread_comments(bigint);
create or replace function public.get_all_thread_comments(p_thread_id bigint)
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
  from public.visitor_thread_comments c
  where c.thread_id = p_thread_id
  order by c.created_at, c.id;
$$;

-- 3. Let any visitor comment on any thread (not just their own)
create or replace function public.add_comment_to_thread(
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
  if p_visitor_token is null then
    raise exception 'A session token is required to comment.';
  end if;
  if not exists (select 1 from public.visitor_threads where id = p_thread_id) then
    raise exception 'This thread could not be found.';
  end if;

  v_content := btrim(coalesce(p_content, ''));
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  if char_length(v_content) not between 1 and 1000 then
    raise exception 'Comments must be between 1 and 1,000 characters.';
  end if;
  if char_length(v_name) > 60 then
    raise exception 'Names must be 60 characters or fewer.';
  end if;

  -- Rate-limit: 3-second cooldown per visitor per thread
  select max(created_at) into v_last_comment
  from public.visitor_thread_comments
  where thread_id = p_thread_id and visitor_token = p_visitor_token;
  if v_last_comment > now() - interval '3 seconds' then
    raise exception 'Please wait a moment before commenting again.';
  end if;

  insert into public.visitor_thread_comments
    (thread_id, visitor_token, sender, sender_label, content)
  values
    (p_thread_id, p_visitor_token, 'visitor', v_name, v_content)
  returning id into v_comment_id;
  return v_comment_id;
end;
$$;

revoke all on function public.get_all_visitor_threads() from public, anon, authenticated;
revoke all on function public.get_all_thread_comments(bigint) from public, anon, authenticated;
revoke all on function public.add_comment_to_thread(uuid, bigint, text, text) from public, anon, authenticated;

grant execute on function public.get_all_visitor_threads() to anon, authenticated;
grant execute on function public.get_all_thread_comments(bigint) to anon, authenticated;
grant execute on function public.add_comment_to_thread(uuid, bigint, text, text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Allow visitors to delete their own comments ──────────────────────────────
create or replace function public.delete_visitor_thread_comment(
  p_visitor_token uuid,
  p_comment_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_visitor_token is null then
    raise exception 'A session token is required.';
  end if;

  delete from public.visitor_thread_comments
  where id = p_comment_id
    and visitor_token = p_visitor_token
    and sender = 'visitor';

  if not found then
    raise exception 'This comment could not be found for your session.';
  end if;

  return true;
end;
$$;

revoke all on function public.delete_visitor_thread_comment(uuid, bigint) from public, anon, authenticated;
grant execute on function public.delete_visitor_thread_comment(uuid, bigint) to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Update get_all_thread_comments to include visitor_token for ownership check ──
drop function if exists public.get_all_thread_comments(bigint);
create or replace function public.get_all_thread_comments(p_thread_id bigint)
returns table (
  id bigint,
  visitor_token uuid,
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
  select c.id, c.visitor_token, c.sender, c.sender_label, c.content, c.created_at
  from public.visitor_thread_comments c
  where c.thread_id = p_thread_id
  order by c.created_at, c.id;
$$;

notify pgrst, 'reload schema';

-- ── Visitor daily submissions (note + optional photo) ────────────────────────

-- Storage bucket for visitor-uploaded photos
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'visitor-daily-uploads',
  'visitor-daily-uploads',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif']
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can view visitor daily upload photos" on storage.objects;
create policy "Anyone can view visitor daily upload photos"
on storage.objects for select to anon, authenticated
using (bucket_id = 'visitor-daily-uploads');

drop policy if exists "Visitors can upload their own daily photos" on storage.objects;
create policy "Visitors can upload their own daily photos"
on storage.objects for insert to anon, authenticated
with check (
  bucket_id = 'visitor-daily-uploads'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);

drop policy if exists "Visitors can delete their own daily photos" on storage.objects;
create policy "Visitors can delete their own daily photos"
on storage.objects for delete to anon, authenticated
using (
  bucket_id = 'visitor-daily-uploads'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);

-- Table to store visitor submissions
create table if not exists public.visitor_daily_submissions (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  display_name text not null default 'Visitor'
    check (char_length(display_name) between 1 and 60),
  note_title text not null default ''
    check (char_length(note_title) <= 120),
  note_content text not null default ''
    check (char_length(note_content) <= 2000),
  photo_path text
    check (photo_path is null or char_length(photo_path) <= 255),
  created_at timestamptz not null default now(),
  check (
    char_length(btrim(note_title)) > 0
    or char_length(btrim(note_content)) > 0
    or photo_path is not null
  )
);

create index if not exists visitor_daily_submissions_token_idx
  on public.visitor_daily_submissions (visitor_token, created_at desc);
create index if not exists visitor_daily_submissions_created_idx
  on public.visitor_daily_submissions (created_at desc);

alter table public.visitor_daily_submissions enable row level security;
revoke all on public.visitor_daily_submissions from anon, authenticated;
grant select on public.visitor_daily_submissions to authenticated;
grant usage, select on sequence public.visitor_daily_submissions_id_seq to authenticated;

drop policy if exists "Only the listed owner can view visitor submissions" on public.visitor_daily_submissions;
create policy "Only the listed owner can view visitor submissions"
on public.visitor_daily_submissions for select to authenticated
using ((select public.is_log_admin()));

-- RPC: submit a daily note + optional photo
create or replace function public.submit_visitor_daily(
  p_visitor_token uuid,
  p_display_name text,
  p_note_title text,
  p_note_content text,
  p_photo_path text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_title text;
  v_content text;
  v_id bigint;
  v_last timestamptz;
begin
  if p_visitor_token is null then
    raise exception 'A session token is required.';
  end if;

  v_name    := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_title   := btrim(coalesce(p_note_title, ''));
  v_content := btrim(coalesce(p_note_content, ''));

  if char_length(v_name) > 60 then
    raise exception 'Name must be 60 characters or fewer.';
  end if;
  if char_length(v_title) > 120 then
    raise exception 'Title must be 120 characters or fewer.';
  end if;
  if char_length(v_content) > 2000 then
    raise exception 'Note must be 2,000 characters or fewer.';
  end if;
  if v_title = '' and v_content = '' and p_photo_path is null then
    raise exception 'Write something or add a photo before sharing.';
  end if;
  if p_photo_path is not null then
    if char_length(p_photo_path) > 255
      or split_part(p_photo_path, '/', 1) <> p_visitor_token::text
      or split_part(p_photo_path, '/', 2) = ''
      or split_part(p_photo_path, '/', 3) <> ''
    then
      raise exception 'The photo does not belong to this session.';
    end if;
    if not exists (
      select 1 from storage.objects
      where bucket_id = 'visitor-daily-uploads' and name = p_photo_path
    ) then
      raise exception 'The uploaded photo could not be found.';
    end if;
  end if;

  -- Rate limit: one submission per visitor every 60 seconds
  select max(created_at) into v_last
  from public.visitor_daily_submissions
  where visitor_token = p_visitor_token;
  if v_last > now() - interval '60 seconds' then
    raise exception 'Please wait a moment before sharing again.';
  end if;

  insert into public.visitor_daily_submissions
    (visitor_token, display_name, note_title, note_content, photo_path)
  values
    (p_visitor_token, v_name, v_title, v_content, p_photo_path)
  returning id into v_id;
  return v_id;
end;
$$;

-- RPC: load this visitor's own submissions
create or replace function public.get_my_visitor_submissions(p_visitor_token uuid)
returns table (
  id bigint,
  display_name text,
  note_title text,
  note_content text,
  photo_path text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select id, display_name, note_title, note_content, photo_path, created_at
  from public.visitor_daily_submissions
  where visitor_token = p_visitor_token
  order by created_at desc, id desc
  limit 20;
$$;

-- RPC: delete visitor's own submission
create or replace function public.delete_visitor_submission(
  p_visitor_token uuid,
  p_submission_id bigint
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.visitor_daily_submissions
  where id = p_submission_id and visitor_token = p_visitor_token;
  if not found then
    raise exception 'This submission could not be found for your session.';
  end if;
  return true;
end;
$$;

revoke all on function public.submit_visitor_daily(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.get_my_visitor_submissions(uuid) from public, anon, authenticated;
revoke all on function public.delete_visitor_submission(uuid, bigint) from public, anon, authenticated;

grant execute on function public.submit_visitor_daily(uuid, text, text, text, text) to anon, authenticated;
grant execute on function public.get_my_visitor_submissions(uuid) to anon, authenticated;
grant execute on function public.delete_visitor_submission(uuid, bigint) to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Threads: video support, comment media, admin posting, comment editing ────

-- 1. Add media columns to visitor_threads (alongside existing image_path)
alter table public.visitor_threads
  add column if not exists media_path text
    check (media_path is null or char_length(media_path) <= 255),
  add column if not exists media_type text
    check (media_type is null or media_type in ('image', 'video')),
  add column if not exists is_owner_post boolean not null default false;

-- 2. Add media + edit columns to visitor_thread_comments
alter table public.visitor_thread_comments
  add column if not exists media_path text
    check (media_path is null or char_length(media_path) <= 255),
  add column if not exists media_type text
    check (media_type is null or media_type in ('image', 'video')),
  add column if not exists updated_at timestamptz;

-- 3. Expand visitor-thread-images bucket to allow videos
update storage.buckets
set
  file_size_limit = 104857600,
  allowed_mime_types = array[
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/avif',
    'video/mp4', 'video/webm', 'video/quicktime'
  ]
where id = 'visitor-thread-images';

-- 4. Allow visitors to delete their own thread media files
drop policy if exists "Visitors can delete their own thread media" on storage.objects;
create policy "Visitors can delete their own thread media"
on storage.objects for delete to anon, authenticated
using (
  bucket_id = 'visitor-thread-images'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);

-- 5. Grant comment update permission for edit support
grant update (content, updated_at) on public.visitor_thread_comments to authenticated;

-- 6. get_all_visitor_threads — now includes media_path, media_type, is_owner_post
drop function if exists public.get_all_visitor_threads();
create or replace function public.get_all_visitor_threads()
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
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select t.id, t.visitor_token, t.display_name, t.content,
         t.image_path, t.media_path, t.media_type, t.is_owner_post,
         t.created_at, t.updated_at
  from public.visitor_threads t
  order by t.created_at desc, t.id desc;
$$;

-- 7. get_all_thread_comments — now includes media_path, media_type
drop function if exists public.get_all_thread_comments(bigint);
create or replace function public.get_all_thread_comments(p_thread_id bigint)
returns table (
  id bigint,
  visitor_token uuid,
  sender text,
  sender_label text,
  content text,
  media_path text,
  media_type text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.visitor_token, c.sender, c.sender_label, c.content,
         c.media_path, c.media_type, c.created_at, c.updated_at
  from public.visitor_thread_comments c
  where c.thread_id = p_thread_id
  order by c.created_at, c.id;
$$;

-- 8. create_visitor_thread — updated to accept media_path + media_type
create or replace function public.create_visitor_thread(
  p_visitor_token uuid,
  p_display_name text,
  p_content text,
  p_image_path text,
  p_media_path text default null,
  p_media_type text default null
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
  v_media_path text := p_media_path;
  v_media_type text := p_media_type;
begin
  if p_visitor_token is null then
    raise exception 'A private thread session is required.';
  end if;
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if char_length(v_content) > 2000 then raise exception 'Threads must be 2,000 characters or fewer.'; end if;
  if v_content = '' and p_image_path is null and v_media_path is null then
    raise exception 'Write something or add a photo or video before posting.';
  end if;
  if v_media_type is not null and v_media_type not in ('image','video') then
    raise exception 'Invalid media type.';
  end if;
  if v_media_path is not null then
    if char_length(v_media_path) > 255
      or split_part(v_media_path, '/', 1) <> p_visitor_token::text then
      raise exception 'The media file does not belong to this session.';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'visitor-thread-images' and name = v_media_path) then
      raise exception 'The uploaded media file could not be found.';
    end if;
  end if;
  insert into public.visitor_threads (visitor_token, display_name, content, image_path, media_path, media_type)
  values (p_visitor_token, v_name, v_content, p_image_path, v_media_path, v_media_type)
  returning id into v_thread_id;
  return v_thread_id;
end;
$$;

-- 9. update_visitor_thread — updated to accept media_path + media_type
create or replace function public.update_visitor_thread(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text,
  p_image_path text,
  p_media_path text default null,
  p_media_type text default null
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
  if p_visitor_token is null then raise exception 'A private thread session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if char_length(v_content) > 2000 then raise exception 'Threads must be 2,000 characters or fewer.'; end if;
  if v_content = '' and p_image_path is null and p_media_path is null then
    raise exception 'Write something or keep a photo or video before saving.';
  end if;
  if p_media_path is not null then
    if char_length(p_media_path) > 255
      or split_part(p_media_path, '/', 1) <> p_visitor_token::text then
      raise exception 'The media file does not belong to this session.';
    end if;
  end if;
  update public.visitor_threads
  set display_name = v_name, content = v_content,
      image_path = p_image_path, media_path = p_media_path,
      media_type = p_media_type, updated_at = now()
  where id = p_thread_id and visitor_token = p_visitor_token;
  if not found then raise exception 'This thread could not be found for this browser.'; end if;
  return true;
end;
$$;

-- 10. add_comment_to_thread — updated to accept optional media
create or replace function public.add_comment_to_thread(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text,
  p_media_path text default null,
  p_media_type text default null
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
  if p_visitor_token is null then raise exception 'A session token is required to comment.'; end if;
  if not exists (select 1 from public.visitor_threads where id = p_thread_id) then
    raise exception 'This thread could not be found.';
  end if;
  v_content := btrim(coalesce(p_content, ''));
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  if char_length(v_content) > 1000 then raise exception 'Comments must be 1,000 characters or fewer.'; end if;
  if v_content = '' and p_media_path is null then
    raise exception 'Write something or add a photo or video before commenting.';
  end if;
  if char_length(v_name) > 60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if p_media_type is not null and p_media_type not in ('image','video') then
    raise exception 'Invalid media type.';
  end if;
  if p_media_path is not null then
    if char_length(p_media_path) > 255
      or split_part(p_media_path, '/', 1) <> p_visitor_token::text then
      raise exception 'The media file does not belong to this session.';
    end if;
    if not exists (select 1 from storage.objects where bucket_id = 'visitor-thread-images' and name = p_media_path) then
      raise exception 'The uploaded media could not be found.';
    end if;
  end if;
  select max(created_at) into v_last_comment
  from public.visitor_thread_comments
  where thread_id = p_thread_id and visitor_token = p_visitor_token;
  if v_last_comment > now() - interval '3 seconds' then
    raise exception 'Please wait a moment before commenting again.';
  end if;
  insert into public.visitor_thread_comments
    (thread_id, visitor_token, sender, sender_label, content, media_path, media_type)
  values
    (p_thread_id, p_visitor_token, 'visitor', v_name, v_content, p_media_path, p_media_type)
  returning id into v_comment_id;
  return v_comment_id;
end;
$$;

-- 11. edit_visitor_thread_comment — new: visitor can edit their own comment text
create or replace function public.edit_visitor_thread_comment(
  p_visitor_token uuid,
  p_comment_id bigint,
  p_content text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_content text;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_content) not between 1 and 1000 then
    raise exception 'Comments must be between 1 and 1,000 characters.';
  end if;
  update public.visitor_thread_comments
  set content = v_content, updated_at = now()
  where id = p_comment_id
    and visitor_token = p_visitor_token
    and sender = 'visitor';
  if not found then raise exception 'This comment could not be found for your session.'; end if;
  return true;
end;
$$;

-- 12. create_owner_thread — admin can post a thread everyone sees
create or replace function public.create_owner_thread(
  p_display_name text,
  p_content text,
  p_media_path text default null,
  p_media_type text default null
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
  if not (select public.is_log_admin()) then
    raise exception 'Only the owner can post owner threads.';
  end if;
  v_name := coalesce(nullif(btrim(p_display_name), ''), 'Owner');
  v_content := btrim(coalesce(p_content, ''));
  if char_length(v_name) > 60 then raise exception 'Name must be 60 characters or fewer.'; end if;
  if char_length(v_content) > 2000 then raise exception 'Thread must be 2,000 characters or fewer.'; end if;
  if v_content = '' and p_media_path is null then
    raise exception 'Write something or add media before posting.';
  end if;
  if p_media_type is not null and p_media_type not in ('image','video') then
    raise exception 'Invalid media type.';
  end if;
  -- Owner threads use a nil UUID as token (never matches a real visitor)
  insert into public.visitor_threads
    (visitor_token, display_name, content, media_path, media_type, is_owner_post)
  values
    ('00000000-0000-0000-0000-000000000000'::uuid, v_name, v_content, p_media_path, p_media_type, true)
  returning id into v_thread_id;
  return v_thread_id;
end;
$$;

-- 13. Revoke/grant all updated and new functions
revoke all on function public.get_all_visitor_threads() from public, anon, authenticated;
revoke all on function public.get_all_thread_comments(bigint) from public, anon, authenticated;
revoke all on function public.create_visitor_thread(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.create_visitor_thread(uuid, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.update_visitor_thread(uuid, bigint, text, text, text) from public, anon, authenticated;
revoke all on function public.update_visitor_thread(uuid, bigint, text, text, text, text, text) from public, anon, authenticated;
revoke all on function public.add_comment_to_thread(uuid, bigint, text, text) from public, anon, authenticated;
revoke all on function public.add_comment_to_thread(uuid, bigint, text, text, text, text) from public, anon, authenticated;
revoke all on function public.edit_visitor_thread_comment(uuid, bigint, text) from public, anon, authenticated;
revoke all on function public.create_owner_thread(text, text, text, text) from public, anon, authenticated;

grant execute on function public.get_all_visitor_threads() to anon, authenticated;
grant execute on function public.get_all_thread_comments(bigint) to anon, authenticated;
grant execute on function public.create_visitor_thread(uuid, text, text, text, text, text) to anon, authenticated;
grant execute on function public.update_visitor_thread(uuid, bigint, text, text, text, text, text) to anon, authenticated;
grant execute on function public.add_comment_to_thread(uuid, bigint, text, text, text, text) to anon, authenticated;
grant execute on function public.edit_visitor_thread_comment(uuid, bigint, text) to anon, authenticated;
grant execute on function public.create_owner_thread(text, text, text, text) to authenticated;

notify pgrst, 'reload schema';

-- ── Allow owner to upload media to visitor-thread-images bucket ──────────────
drop policy if exists "Owner can upload thread media" on storage.objects;
create policy "Owner can upload thread media"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'visitor-thread-images'
  and (select public.is_log_admin())
);

drop policy if exists "Owner can delete thread media" on storage.objects;
create policy "Owner can delete thread media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'visitor-thread-images'
  and (select public.is_log_admin())
);

-- Allow insert on visitor_thread_comments media columns (they were added via ALTER)
-- The existing insert policy already covers it since it only checks sender/sender_label/visitor_token
-- No additional policy needed for media_path/media_type columns

notify pgrst, 'reload schema';

-- ── Daily note replies (visitors reply to the daily note, admin sees them) ───

create table if not exists public.daily_note_replies (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  display_name text not null default 'Visitor'
    check (char_length(display_name) between 1 and 60),
  note_id text not null
    check (char_length(note_id) between 1 and 20),
  message text not null
    check (char_length(message) between 1 and 500 and message = btrim(message)),
  created_at timestamptz not null default now()
);

create index if not exists daily_note_replies_created_idx
  on public.daily_note_replies (created_at desc, id desc);

alter table public.daily_note_replies enable row level security;
revoke all on public.daily_note_replies from anon, authenticated;
grant select on public.daily_note_replies to authenticated;
grant usage, select on sequence public.daily_note_replies_id_seq to authenticated;

drop policy if exists "Only the listed owner can view daily note replies" on public.daily_note_replies;
create policy "Only the listed owner can view daily note replies"
on public.daily_note_replies for select to authenticated
using ((select public.is_log_admin()));

create or replace function public.submit_daily_note_reply(
  p_visitor_token uuid,
  p_display_name text,
  p_note_id text,
  p_message text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_message text;
  v_id bigint;
  v_last timestamptz;
begin
  if p_visitor_token is null then
    raise exception 'A session token is required.';
  end if;

  v_name    := coalesce(nullif(btrim(p_display_name), ''), 'Visitor');
  v_message := btrim(coalesce(p_message, ''));

  if char_length(v_name) > 60 then
    raise exception 'Name must be 60 characters or fewer.';
  end if;
  if char_length(v_message) not between 1 and 500 then
    raise exception 'Reply must be between 1 and 500 characters.';
  end if;
  if p_note_id is null or char_length(p_note_id) = 0 then
    raise exception 'Note ID is required.';
  end if;

  -- Rate limit: one reply per visitor per note per 30 seconds
  select max(created_at) into v_last
  from public.daily_note_replies
  where visitor_token = p_visitor_token and note_id = p_note_id;
  if v_last > now() - interval '30 seconds' then
    raise exception 'Please wait a moment before replying again.';
  end if;

  insert into public.daily_note_replies (visitor_token, display_name, note_id, message)
  values (p_visitor_token, v_name, p_note_id, v_message)
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.submit_daily_note_reply(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.submit_daily_note_reply(uuid, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Remove character limits on threads and comments ──────────────────────────

-- Raise thread content limit to 100,000 characters (effectively unlimited)
alter table public.visitor_threads
  drop constraint if exists visitor_threads_content_check;
alter table public.visitor_threads
  add constraint visitor_threads_content_check
  check (char_length(content) <= 100000);

-- Raise comment content limit to 100,000 characters
alter table public.visitor_thread_comments
  drop constraint if exists visitor_thread_comments_content_check;
alter table public.visitor_thread_comments
  add constraint visitor_thread_comments_content_check
  check (char_length(content) <= 100000 and content = btrim(content));

-- Update create_visitor_thread to allow long content
create or replace function public.create_visitor_thread(p_visitor_token uuid, p_display_name text, p_content text, p_image_path text, p_media_path text default null, p_media_type text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_name text; v_content text; v_thread_id bigint;
begin
  if p_visitor_token is null then raise exception 'A private thread session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  v_content := btrim(coalesce(p_content,''));
  if char_length(v_name)>60 then raise exception 'Names must be 60 characters or fewer.'; end if;
  if v_content='' and p_image_path is null and p_media_path is null then raise exception 'Write something or add media before posting.'; end if;
  if p_media_path is not null and (char_length(p_media_path)>255 or split_part(p_media_path,'/',1)<>p_visitor_token::text) then raise exception 'The media file does not belong to this session.'; end if;
  if p_media_path is not null and not exists(select 1 from storage.objects where bucket_id='visitor-thread-images' and name=p_media_path) then raise exception 'The uploaded media file could not be found.'; end if;
  insert into public.visitor_threads(visitor_token,display_name,content,image_path,media_path,media_type)
  values(p_visitor_token,v_name,v_content,p_image_path,p_media_path,p_media_type) returning id into v_thread_id;
  return v_thread_id;
end;$$;

-- Update update_visitor_thread to allow long content
create or replace function public.update_visitor_thread(p_visitor_token uuid, p_thread_id bigint, p_display_name text, p_content text, p_image_path text, p_media_path text default null, p_media_type text default null)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_name text; v_content text;
begin
  if p_visitor_token is null then raise exception 'A private thread session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  v_content := btrim(coalesce(p_content,''));
  if v_content='' and p_image_path is null and p_media_path is null then raise exception 'Write something or keep media before saving.'; end if;
  update public.visitor_threads set display_name=v_name, content=v_content, image_path=p_image_path, media_path=p_media_path, media_type=p_media_type, updated_at=now()
  where id=p_thread_id and visitor_token=p_visitor_token;
  if not found then raise exception 'This thread could not be found for this browser.'; end if;
  return true;
end;$$;

-- Update add_comment_to_thread to allow long comments
create or replace function public.add_comment_to_thread(p_visitor_token uuid, p_thread_id bigint, p_display_name text, p_content text, p_media_path text default null, p_media_type text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_content text; v_name text; v_last timestamptz; v_id bigint;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  if not exists(select 1 from public.visitor_threads where id=p_thread_id) then raise exception 'Thread not found.'; end if;
  v_content := btrim(coalesce(p_content,''));
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  if v_content='' and p_media_path is null then raise exception 'Write something or add media before commenting.'; end if;
  if p_media_path is not null and (char_length(p_media_path)>255 or split_part(p_media_path,'/',1)<>p_visitor_token::text) then raise exception 'Media does not belong to this session.'; end if;
  if p_media_path is not null and not exists(select 1 from storage.objects where bucket_id='visitor-thread-images' and name=p_media_path) then raise exception 'Uploaded media not found.'; end if;
  select max(created_at) into v_last from public.visitor_thread_comments where thread_id=p_thread_id and visitor_token=p_visitor_token;
  if v_last > now()-interval '3 seconds' then raise exception 'Please wait before commenting again.'; end if;
  insert into public.visitor_thread_comments(thread_id,visitor_token,sender,sender_label,content,media_path,media_type)
  values(p_thread_id,p_visitor_token,'visitor',v_name,v_content,p_media_path,p_media_type) returning id into v_id;
  return v_id;
end;$$;

-- Update edit_visitor_thread_comment to allow long comments
create or replace function public.edit_visitor_thread_comment(p_visitor_token uuid, p_comment_id bigint, p_content text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_content text;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  v_content := btrim(coalesce(p_content,''));
  if char_length(v_content) = 0 then raise exception 'Comment cannot be empty.'; end if;
  update public.visitor_thread_comments set content=v_content, updated_at=now()
  where id=p_comment_id and visitor_token=p_visitor_token and sender='visitor';
  if not found then raise exception 'Comment not found for your session.'; end if;
  return true;
end;$$;

-- Update create_owner_thread to allow long content
create or replace function public.create_owner_thread(p_display_name text, p_content text, p_media_path text default null, p_media_type text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_thread_id bigint;
begin
  if not (select public.is_log_admin()) then raise exception 'Only the owner can post owner threads.'; end if;
  if btrim(coalesce(p_content,''))='' and p_media_path is null then raise exception 'Write something or add media before posting.'; end if;
  insert into public.visitor_threads(visitor_token,display_name,content,media_path,media_type,is_owner_post)
  values('00000000-0000-0000-0000-000000000000'::uuid,coalesce(nullif(btrim(p_display_name),''),'Owner'),btrim(coalesce(p_content,'')),p_media_path,p_media_type,true)
  returning id into v_thread_id;
  return v_thread_id;
end;$$;

grant execute on function public.create_visitor_thread(uuid,text,text,text,text,text) to anon, authenticated;
grant execute on function public.update_visitor_thread(uuid,bigint,text,text,text,text,text) to anon, authenticated;
grant execute on function public.add_comment_to_thread(uuid,bigint,text,text,text,text) to anon, authenticated;
grant execute on function public.edit_visitor_thread_comment(uuid,bigint,text) to anon, authenticated;
grant execute on function public.create_owner_thread(text,text,text,text) to authenticated;

notify pgrst, 'reload schema';

-- ── Thread reactions and comment replies ─────────────────────────────────────

-- Reactions on threads and comments
create table if not exists public.thread_reactions (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  target_type text not null check (target_type in ('thread', 'comment')),
  target_id bigint not null,
  emoji text not null check (emoji in ('like','love','haha','wow','sad')),
  created_at timestamptz not null default now(),
  unique (visitor_token, target_type, target_id)
);

create index if not exists thread_reactions_target_idx
  on public.thread_reactions (target_type, target_id);

alter table public.thread_reactions enable row level security;
revoke all on public.thread_reactions from anon, authenticated;
grant usage, select on sequence public.thread_reactions_id_seq to anon, authenticated;

drop policy if exists "Anyone can view thread reactions" on public.thread_reactions;
create policy "Anyone can view thread reactions"
on public.thread_reactions for select to anon, authenticated using (true);

-- Toggle reaction: set or change emoji; remove if same emoji clicked again
create or replace function public.toggle_thread_reaction(
  p_visitor_token uuid,
  p_target_type text,
  p_target_id bigint,
  p_emoji text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing text;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  if p_target_type not in ('thread','comment') then raise exception 'Invalid target type.'; end if;
  if p_emoji not in ('like','love','haha','wow','sad') then raise exception 'Invalid emoji.'; end if;

  select emoji into v_existing
  from public.thread_reactions
  where visitor_token = p_visitor_token
    and target_type = p_target_type
    and target_id = p_target_id;

  if v_existing is null then
    -- No reaction yet — add it
    insert into public.thread_reactions(visitor_token, target_type, target_id, emoji)
    values(p_visitor_token, p_target_type, p_target_id, p_emoji);
  elsif v_existing = p_emoji then
    -- Same emoji — remove it (toggle off)
    delete from public.thread_reactions
    where visitor_token = p_visitor_token
      and target_type = p_target_type
      and target_id = p_target_id;
  else
    -- Different emoji — replace it
    update public.thread_reactions
    set emoji = p_emoji, created_at = now()
    where visitor_token = p_visitor_token
      and target_type = p_target_type
      and target_id = p_target_id;
  end if;
end;
$$;

-- Get reaction counts + current visitor's reaction for a list of targets
create or replace function public.get_thread_reactions(
  p_visitor_token uuid,
  p_target_type text,
  p_target_ids bigint[]
)
returns table (
  target_id bigint,
  emoji text,
  reaction_count bigint,
  my_reaction text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    r.target_id,
    r.emoji,
    count(*) as reaction_count,
    max(case when r.visitor_token = p_visitor_token then r.emoji end) as my_reaction
  from public.thread_reactions r
  where r.target_type = p_target_type
    and r.target_id = any(p_target_ids)
  group by r.target_id, r.emoji;
$$;

-- Comment replies: add parent_comment_id to visitor_thread_comments
alter table public.visitor_thread_comments
  add column if not exists parent_comment_id bigint
    references public.visitor_thread_comments(id) on delete cascade;

create index if not exists visitor_thread_comments_parent_idx
  on public.visitor_thread_comments (parent_comment_id)
  where parent_comment_id is not null;

-- Update get_all_thread_comments to include parent_comment_id
drop function if exists public.get_all_thread_comments(bigint);
create or replace function public.get_all_thread_comments(p_thread_id bigint)
returns table (
  id bigint,
  visitor_token uuid,
  sender text,
  sender_label text,
  content text,
  media_path text,
  media_type text,
  parent_comment_id bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select c.id, c.visitor_token, c.sender, c.sender_label, c.content,
         c.media_path, c.media_type, c.parent_comment_id, c.created_at, c.updated_at
  from public.visitor_thread_comments c
  where c.thread_id = p_thread_id
  order by c.created_at, c.id;
$$;

-- Update add_comment_to_thread to accept optional parent_comment_id
create or replace function public.add_comment_to_thread(
  p_visitor_token uuid,
  p_thread_id bigint,
  p_display_name text,
  p_content text,
  p_media_path text default null,
  p_media_type text default null,
  p_parent_comment_id bigint default null
)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_content text; v_name text; v_last timestamptz; v_id bigint;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  if not exists(select 1 from public.visitor_threads where id=p_thread_id) then raise exception 'Thread not found.'; end if;
  v_content := btrim(coalesce(p_content,''));
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  if v_content='' and p_media_path is null then raise exception 'Write something or add media before commenting.'; end if;
  if p_media_path is not null and (char_length(p_media_path)>255 or split_part(p_media_path,'/',1)<>p_visitor_token::text) then raise exception 'Media does not belong to this session.'; end if;
  if p_media_path is not null and not exists(select 1 from storage.objects where bucket_id='visitor-thread-images' and name=p_media_path) then raise exception 'Uploaded media not found.'; end if;
  if p_parent_comment_id is not null and not exists(select 1 from public.visitor_thread_comments where id=p_parent_comment_id and thread_id=p_thread_id) then raise exception 'Parent comment not found.'; end if;
  select max(created_at) into v_last from public.visitor_thread_comments where thread_id=p_thread_id and visitor_token=p_visitor_token;
  if v_last > now()-interval '3 seconds' then raise exception 'Please wait before commenting again.'; end if;
  insert into public.visitor_thread_comments(thread_id,visitor_token,sender,sender_label,content,media_path,media_type,parent_comment_id)
  values(p_thread_id,p_visitor_token,'visitor',v_name,v_content,p_media_path,p_media_type,p_parent_comment_id) returning id into v_id;
  return v_id;
end;$$;

revoke all on function public.toggle_thread_reaction(uuid,text,bigint,text) from public, anon, authenticated;
revoke all on function public.get_thread_reactions(uuid,text,bigint[]) from public, anon, authenticated;
revoke all on function public.get_all_thread_comments(bigint) from public, anon, authenticated;
revoke all on function public.add_comment_to_thread(uuid,bigint,text,text,text,text) from public, anon, authenticated;
revoke all on function public.add_comment_to_thread(uuid,bigint,text,text,text,text,bigint) from public, anon, authenticated;

grant execute on function public.toggle_thread_reaction(uuid,text,bigint,text) to anon, authenticated;
grant execute on function public.get_thread_reactions(uuid,text,bigint[]) to anon, authenticated;
grant execute on function public.get_all_thread_comments(bigint) to anon, authenticated;
grant execute on function public.add_comment_to_thread(uuid,bigint,text,text,text,text,bigint) to anon, authenticated;

-- Grant insert/delete on thread_reactions for anon
grant insert, delete on public.thread_reactions to anon, authenticated;
grant update on public.thread_reactions to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Update create_owner_thread to use Vren as default display name ───────────
create or replace function public.create_owner_thread(p_display_name text, p_content text, p_media_path text default null, p_media_type text default null)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare v_thread_id bigint;
begin
  if not (select public.is_log_admin()) then raise exception 'Only the owner can post owner threads.'; end if;
  if btrim(coalesce(p_content,''))='' and p_media_path is null then raise exception 'Write something or add media before posting.'; end if;
  insert into public.visitor_threads(visitor_token,display_name,content,media_path,media_type,is_owner_post)
  values('00000000-0000-0000-0000-000000000000'::uuid, coalesce(nullif(btrim(p_display_name),''),'Vren'), btrim(coalesce(p_content,'')), p_media_path, p_media_type, true)
  returning id into v_thread_id;
  return v_thread_id;
end;$$;

grant execute on function public.create_owner_thread(text,text,text,text) to authenticated;

notify pgrst, 'reload schema';

-- ── DM Chat: extend site_chat_messages + fix grants ─────────────────────────

-- Add media, reply_to, and edit support to site_chat_messages
alter table public.site_chat_messages
  add column if not exists media_path text
    check (media_path is null or char_length(media_path) <= 255),
  add column if not exists media_type text
    check (media_type is null or media_type in ('image','video')),
  add column if not exists reply_to_id bigint
    references public.site_chat_messages(id) on delete set null,
  add column if not exists reply_preview text
    check (reply_preview is null or char_length(reply_preview) <= 200),
  add column if not exists updated_at timestamptz,
  add column if not exists is_deleted boolean not null default false;

-- Remove old character limit on message (allow longer messages)
alter table public.site_chat_messages
  drop constraint if exists site_chat_messages_message_check;
alter table public.site_chat_messages
  add constraint site_chat_messages_message_check
  check (char_length(message) <= 100000 and message = btrim(message));

-- Reactions on chat messages
create table if not exists public.chat_message_reactions (
  id bigint generated always as identity primary key,
  message_id bigint not null references public.site_chat_messages(id) on delete cascade,
  visitor_token uuid not null,
  emoji text not null check (emoji in ('like','love','haha','wow','sad')),
  created_at timestamptz not null default now(),
  unique (message_id, visitor_token)
);
create index if not exists chat_reactions_msg_idx on public.chat_message_reactions (message_id);
alter table public.chat_message_reactions enable row level security;
revoke all on public.chat_message_reactions from anon, authenticated;
grant usage, select on sequence public.chat_message_reactions_id_seq to anon, authenticated;
grant insert, update, delete on public.chat_message_reactions to anon, authenticated;
drop policy if exists "Anyone can view chat reactions" on public.chat_message_reactions;
create policy "Anyone can view chat reactions"
on public.chat_message_reactions for select to anon, authenticated using (true);

-- Storage bucket for chat media
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media', 'chat-media', true, 104857600,
  array['image/jpeg','image/png','image/gif','image/webp','image/avif','video/mp4','video/webm','video/quicktime']
)
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Anyone can view chat media" on storage.objects;
create policy "Anyone can view chat media"
on storage.objects for select to anon, authenticated using (bucket_id = 'chat-media');

drop policy if exists "Visitors can upload chat media" on storage.objects;
create policy "Visitors can upload chat media"
on storage.objects for insert to anon, authenticated
with check (
  bucket_id = 'chat-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
);

drop policy if exists "Owner can upload chat media" on storage.objects;
create policy "Owner can upload chat media"
on storage.objects for insert to authenticated
with check (bucket_id = 'chat-media' and (select public.is_log_admin()));

-- Fix: grant execute on existing chat RPCs (were missing)
grant execute on function public.get_visitor_chat_messages(uuid) to anon, authenticated;
grant execute on function public.send_visitor_chat_message(uuid, text, text) to anon, authenticated;

-- New RPC: send chat message with media + reply support
create or replace function public.send_chat_message(
  p_visitor_token uuid,
  p_display_name text,
  p_message text,
  p_media_path text default null,
  p_media_type text default null,
  p_reply_to_id bigint default null,
  p_reply_preview text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_thread_id bigint;
  v_last timestamptz;
  v_msg_id bigint;
  v_name text;
  v_msg text;
begin
  if p_visitor_token is null then raise exception 'A chat session is required.'; end if;
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  v_msg := btrim(coalesce(p_message,''));
  if char_length(v_name) > 60 then raise exception 'Name must be 60 characters or fewer.'; end if;
  if v_msg = '' and p_media_path is null then raise exception 'Write something or add media.'; end if;

  insert into public.site_chat_threads (visitor_token, display_name)
  values (p_visitor_token, v_name)
  on conflict (visitor_token) do update set display_name = excluded.display_name
  returning id into v_thread_id;

  select max(created_at) into v_last
  from public.site_chat_messages
  where thread_id = v_thread_id and sender = 'visitor';
  if v_last > now() - interval '2 seconds' then raise exception 'Please wait before sending again.'; end if;

  insert into public.site_chat_messages (thread_id, sender, sender_label, message, media_path, media_type, reply_to_id, reply_preview)
  values (v_thread_id, 'visitor', v_name, v_msg, p_media_path, p_media_type, p_reply_to_id, p_reply_preview)
  returning id into v_msg_id;

  update public.site_chat_threads set last_message_at = now() where id = v_thread_id;
  return v_msg_id;
end;
$$;

-- RPC: get messages with reaction counts for a visitor
create or replace function public.get_chat_messages(p_visitor_token uuid)
returns table (
  id bigint,
  sender text,
  sender_label text,
  message text,
  media_path text,
  media_type text,
  reply_to_id bigint,
  reply_preview text,
  is_deleted boolean,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select m.id, m.sender, m.sender_label, m.message, m.media_path, m.media_type,
         m.reply_to_id, m.reply_preview, m.is_deleted, m.created_at, m.updated_at
  from public.site_chat_threads t
  join public.site_chat_messages m on m.thread_id = t.id
  where t.visitor_token = p_visitor_token
  order by m.id;
$$;

-- RPC: edit visitor's own message
create or replace function public.edit_chat_message(p_visitor_token uuid, p_message_id bigint, p_new_message text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_thread_id bigint; v_msg text;
begin
  if p_visitor_token is null then raise exception 'A session is required.'; end if;
  v_msg := btrim(coalesce(p_new_message,''));
  if char_length(v_msg) = 0 then raise exception 'Message cannot be empty.'; end if;
  select t.id into v_thread_id from public.site_chat_threads t where t.visitor_token = p_visitor_token;
  update public.site_chat_messages set message = v_msg, updated_at = now()
  where id = p_message_id and thread_id = v_thread_id and sender = 'visitor';
  if not found then raise exception 'Message not found for your session.'; end if;
  return true;
end;
$$;

-- RPC: soft-delete visitor's own message
create or replace function public.delete_chat_message(p_visitor_token uuid, p_message_id bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare v_thread_id bigint;
begin
  if p_visitor_token is null then raise exception 'A session is required.'; end if;
  select t.id into v_thread_id from public.site_chat_threads t where t.visitor_token = p_visitor_token;
  update public.site_chat_messages set is_deleted = true, message = '', updated_at = now()
  where id = p_message_id and thread_id = v_thread_id and sender = 'visitor';
  if not found then raise exception 'Message not found for your session.'; end if;
  return true;
end;
$$;

-- RPC: toggle reaction on a chat message
create or replace function public.toggle_chat_reaction(p_visitor_token uuid, p_message_id bigint, p_emoji text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_existing text;
begin
  if p_visitor_token is null then raise exception 'A session is required.'; end if;
  if p_emoji not in ('like','love','haha','wow','sad') then raise exception 'Invalid emoji.'; end if;
  select emoji into v_existing from public.chat_message_reactions
  where message_id = p_message_id and visitor_token = p_visitor_token;
  if v_existing is null then
    insert into public.chat_message_reactions (message_id, visitor_token, emoji) values (p_message_id, p_visitor_token, p_emoji);
  elsif v_existing = p_emoji then
    delete from public.chat_message_reactions where message_id = p_message_id and visitor_token = p_visitor_token;
  else
    update public.chat_message_reactions set emoji = p_emoji where message_id = p_message_id and visitor_token = p_visitor_token;
  end if;
end;
$$;

-- RPC: get reaction counts for a list of message ids
create or replace function public.get_chat_reactions(p_visitor_token uuid, p_message_ids bigint[])
returns table (message_id bigint, emoji text, reaction_count bigint, my_reaction text)
language sql
stable
security definer
set search_path = ''
as $$
  select r.message_id, r.emoji, count(*) as reaction_count,
         max(case when r.visitor_token = p_visitor_token then r.emoji end) as my_reaction
  from public.chat_message_reactions r
  where r.message_id = any(p_message_ids)
  group by r.message_id, r.emoji;
$$;

-- Grant everything
grant update (message, is_deleted, updated_at, media_path, media_type, reply_to_id, reply_preview) on public.site_chat_messages to authenticated;

revoke all on function public.send_chat_message(uuid,text,text,text,text,bigint,text) from public, anon, authenticated;
revoke all on function public.get_chat_messages(uuid) from public, anon, authenticated;
revoke all on function public.edit_chat_message(uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.delete_chat_message(uuid,bigint) from public, anon, authenticated;
revoke all on function public.toggle_chat_reaction(uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.get_chat_reactions(uuid,bigint[]) from public, anon, authenticated;

grant execute on function public.send_chat_message(uuid,text,text,text,text,bigint,text) to anon, authenticated;
grant execute on function public.get_chat_messages(uuid) to anon, authenticated;
grant execute on function public.edit_chat_message(uuid,bigint,text) to anon, authenticated;
grant execute on function public.delete_chat_message(uuid,bigint) to anon, authenticated;
grant execute on function public.toggle_chat_reaction(uuid,bigint,text) to anon, authenticated;
grant execute on function public.get_chat_reactions(uuid,bigint[]) to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Allow owner to update chat messages (for soft-delete) ────────────────────
grant update (is_deleted, message, updated_at, media_path, media_type, reply_to_id, reply_preview) on public.site_chat_messages to authenticated;
grant update (last_message_at) on public.site_chat_threads to authenticated;

-- Allow owner to insert with new columns
drop policy if exists "Only the listed owner can reply in chat" on public.site_chat_messages;
create policy "Only the listed owner can reply in chat"
on public.site_chat_messages for insert to authenticated
with check (sender = 'owner' and (select public.is_log_admin()));

-- Allow owner to update (soft delete)
drop policy if exists "Only the listed owner can update chat messages" on public.site_chat_messages;
create policy "Only the listed owner can update chat messages"
on public.site_chat_messages for update to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

-- Allow owner to update thread last_message_at
drop policy if exists "Only the listed owner can update chat threads" on public.site_chat_threads;
create policy "Only the listed owner can update chat threads"
on public.site_chat_threads for update to authenticated
using ((select public.is_log_admin()))
with check ((select public.is_log_admin()));

-- Allow visitors to read chat reaction counts (public)
grant select on public.chat_message_reactions to anon, authenticated;

notify pgrst, 'reload schema';

-- ── Shared group chat (everyone sees all messages) ───────────────────────────

create table if not exists public.group_chat_messages (
  id bigint generated always as identity primary key,
  visitor_token uuid not null,
  display_name text not null default 'Visitor'
    check (char_length(display_name) between 1 and 60),
  is_owner boolean not null default false,
  message text not null default ''
    check (char_length(message) <= 100000),
  media_path text check (media_path is null or char_length(media_path) <= 255),
  media_type text check (media_type is null or media_type in ('image','video')),
  reply_to_id bigint references public.group_chat_messages(id) on delete set null,
  reply_preview text check (reply_preview is null or char_length(reply_preview) <= 200),
  reply_author text check (reply_author is null or char_length(reply_author) <= 60),
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  check (char_length(btrim(message)) > 0 or media_path is not null)
);

create index if not exists group_chat_messages_created_idx
  on public.group_chat_messages (created_at, id);

-- Reactions on group chat
create table if not exists public.group_chat_reactions (
  id bigint generated always as identity primary key,
  message_id bigint not null references public.group_chat_messages(id) on delete cascade,
  visitor_token uuid not null,
  emoji text not null check (emoji in ('like','love','haha','wow','sad')),
  created_at timestamptz not null default now(),
  unique (message_id, visitor_token)
);
create index if not exists group_chat_reactions_msg_idx
  on public.group_chat_reactions (message_id);

alter table public.group_chat_messages enable row level security;
alter table public.group_chat_reactions enable row level security;
revoke all on public.group_chat_messages from anon, authenticated;
revoke all on public.group_chat_reactions from anon, authenticated;
grant usage, select on sequence public.group_chat_messages_id_seq to anon, authenticated;
grant usage, select on sequence public.group_chat_reactions_id_seq to anon, authenticated;

-- Everyone can read all messages and reactions
drop policy if exists "Anyone can view group chat messages" on public.group_chat_messages;
create policy "Anyone can view group chat messages"
on public.group_chat_messages for select to anon, authenticated using (true);

drop policy if exists "Anyone can view group chat reactions" on public.group_chat_reactions;
create policy "Anyone can view group chat reactions"
on public.group_chat_reactions for select to anon, authenticated using (true);

grant insert, update, delete on public.group_chat_reactions to anon, authenticated;

-- Storage for group chat media (reuse chat-media bucket already created)

-- RPC: post a message
create or replace function public.post_group_chat_message(
  p_visitor_token uuid,
  p_display_name text,
  p_message text,
  p_is_owner boolean default false,
  p_media_path text default null,
  p_media_type text default null,
  p_reply_to_id bigint default null,
  p_reply_preview text default null,
  p_reply_author text default null
)
returns bigint language plpgsql security definer set search_path = ''
as $$
declare
  v_name text; v_msg text; v_id bigint; v_last timestamptz;
begin
  if p_visitor_token is null then raise exception 'A session token is required.'; end if;
  if coalesce(p_is_owner, false) and not (select public.is_log_admin()) then
    raise exception 'Only the owner can post as the owner.';
  end if;
  v_name := coalesce(nullif(btrim(p_display_name),''),'Visitor');
  v_msg := btrim(coalesce(p_message,''));
  if char_length(v_name) > 60 then raise exception 'Name must be 60 characters or fewer.'; end if;
  if v_msg = '' and p_media_path is null then raise exception 'Write something or add media.'; end if;
  -- Rate limit: 2 seconds
  select max(created_at) into v_last from public.group_chat_messages where visitor_token = p_visitor_token;
  if v_last > now() - interval '2 seconds' then raise exception 'Please wait before sending again.'; end if;
  insert into public.group_chat_messages
    (visitor_token, display_name, is_owner, message, media_path, media_type, reply_to_id, reply_preview, reply_author)
  values
    (p_visitor_token, v_name, coalesce(p_is_owner, false), v_msg, p_media_path, p_media_type, p_reply_to_id, p_reply_preview, p_reply_author)
  returning id into v_id;
  return v_id;
end;$$;

-- RPC: get the complete conversation history
create or replace function public.get_group_chat_messages()
returns table (
  id bigint, visitor_token uuid, display_name text, is_owner boolean,
  message text, media_path text, media_type text,
  reply_to_id bigint, reply_preview text, reply_author text,
  is_deleted boolean, created_at timestamptz, updated_at timestamptz
)
language sql stable security definer set search_path = ''
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

-- RPC: edit own message
create or replace function public.edit_group_chat_message(p_visitor_token uuid, p_message_id bigint, p_new_message text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare v_msg text;
begin
  v_msg := btrim(coalesce(p_new_message,''));
  update public.group_chat_messages set message = v_msg, updated_at = now()
  where id = p_message_id
    and visitor_token = p_visitor_token
    and (not is_owner or (select public.is_log_admin()))
    and (v_msg <> '' or media_path is not null);
  if not found then raise exception 'Message not found for your session.'; end if;
  return true;
end;$$;

-- RPC: soft-delete own message
create or replace function public.delete_group_chat_message(p_visitor_token uuid, p_message_id bigint)
returns boolean language plpgsql security definer set search_path = ''
as $$
begin
  update public.group_chat_messages set is_deleted = true, message = '', updated_at = now()
  where id = p_message_id
    and visitor_token = p_visitor_token
    and (not is_owner or (select public.is_log_admin()));
  if not found then raise exception 'Message not found for your session.'; end if;
  return true;
end;$$;

-- RPC: toggle reaction
create or replace function public.toggle_group_chat_reaction(p_visitor_token uuid, p_message_id bigint, p_emoji text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_existing text;
begin
  if p_emoji not in ('like','love','haha','wow','sad') then raise exception 'Invalid emoji.'; end if;
  select emoji into v_existing from public.group_chat_reactions
  where message_id = p_message_id and visitor_token = p_visitor_token;
  if v_existing is null then
    insert into public.group_chat_reactions(message_id, visitor_token, emoji) values(p_message_id, p_visitor_token, p_emoji);
  elsif v_existing = p_emoji then
    delete from public.group_chat_reactions where message_id = p_message_id and visitor_token = p_visitor_token;
  else
    update public.group_chat_reactions set emoji = p_emoji where message_id = p_message_id and visitor_token = p_visitor_token;
  end if;
end;$$;

-- RPC: get reactions
create or replace function public.get_group_chat_reactions(p_visitor_token uuid)
returns table (message_id bigint, emoji text, reaction_count bigint, my_reaction text)
language sql stable security definer set search_path = ''
as $$
  select r.message_id, r.emoji, count(*) as reaction_count,
         max(case when r.visitor_token = p_visitor_token then r.emoji end) as my_reaction
  from public.group_chat_reactions r
  group by r.message_id, r.emoji;
$$;

revoke all on function public.post_group_chat_message(uuid,text,text,boolean,text,text,bigint,text,text) from public, anon, authenticated;
revoke all on function public.get_group_chat_messages() from public, anon, authenticated;
revoke all on function public.get_group_chat_messages_page(timestamptz,bigint,integer) from public, anon, authenticated;
revoke all on function public.edit_group_chat_message(uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.delete_group_chat_message(uuid,bigint) from public, anon, authenticated;
revoke all on function public.toggle_group_chat_reaction(uuid,bigint,text) from public, anon, authenticated;
revoke all on function public.get_group_chat_reactions(uuid) from public, anon, authenticated;

grant execute on function public.post_group_chat_message(uuid,text,text,boolean,text,text,bigint,text,text) to anon, authenticated;
grant execute on function public.get_group_chat_messages() to anon, authenticated;
grant execute on function public.get_group_chat_messages_page(timestamptz,bigint,integer) to anon, authenticated;
grant execute on function public.edit_group_chat_message(uuid,bigint,text) to anon, authenticated;
grant execute on function public.delete_group_chat_message(uuid,bigint) to anon, authenticated;
grant execute on function public.toggle_group_chat_reaction(uuid,bigint,text) to anon, authenticated;
grant execute on function public.get_group_chat_reactions(uuid) to anon, authenticated;

notify pgrst, 'reload schema';

-- Thread posts can contain multiple captioned attachments.
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

notify pgrst, 'reload schema';

-- Visitors record when they read owner messages; only the owner can view counts.
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
revoke all on public.group_chat_read_receipts from anon, authenticated;

drop function if exists public.mark_group_chat_seen(uuid, bigint[]);
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

  insert into public.group_chat_read_receipts as existing_receipt (message_id, visitor_token, visitor_name)
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
create or replace function public.get_group_chat_seen_counts()
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
        'name', coalesce(nullif(btrim(r.visitor_name), ''), 'Visitor ' || upper(right(r.visitor_token::text, 4))),
        'read_at', r.read_at
      )
      order by r.read_at, r.visitor_token
    )
  from public.group_chat_read_receipts r
  group by r.message_id;
end;
$$;

revoke all on function public.mark_group_chat_seen(uuid,bigint[],text) from public, anon, authenticated;
revoke all on function public.get_group_chat_seen_counts() from public, anon, authenticated;
grant execute on function public.mark_group_chat_seen(uuid,bigint[],text) to anon, authenticated;
grant execute on function public.get_group_chat_seen_counts() to authenticated;

notify pgrst, 'reload schema';
