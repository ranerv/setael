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

alter database postgres set timezone to 'Asia/Manila';

notify pgrst, 'reload schema';
