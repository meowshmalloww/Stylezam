-- Stylezam private cloud Library.
-- Firebase Auth must be registered in Authentication > Third-party Auth and
-- Firebase users must receive the signed custom claim: role = authenticated.

create extension if not exists vector with schema extensions;

create or replace function public.stylezam_current_owner()
returns text
language sql
stable
as $$
  select nullif(auth.jwt() ->> 'sub', '');
$$;

create table if not exists public.stylezam_cloud_entitlements (
  owner_id text primary key,
  plan text not null default 'free' check (plan in ('free', 'plus', 'pro', 'developer')),
  quota_bytes bigint not null default 262144000 check (quota_bytes >= 0),
  updated_at timestamptz not null default now()
);

-- This table is intentionally server-managed. An App Store Server notification
-- handler or an administrator using the service role updates it after verifying
-- a StoreKit entitlement. The iOS publishable key cannot grant itself storage.
alter table public.stylezam_cloud_entitlements enable row level security;
create policy "owners read their cloud entitlement"
on public.stylezam_cloud_entitlements for select
to authenticated
using (owner_id = public.stylezam_current_owner());

create table if not exists public.stylezam_library_garments (
  record_id text not null,
  owner_id text not null,
  scan_id uuid not null,
  garment_id text not null,
  created_at timestamptz not null,
  origin text not null,
  capture_mode text not null,
  title text not null,
  category text,
  detector_label text not null,
  detector_confidence double precision not null,
  review_state text,
  accepted boolean not null default true,
  colors text[] not null default '{}',
  materials text[] not null default '{}',
  patterns text[] not null default '{}',
  details text[] not null default '{}',
  visible_text text[] not null default '{}',
  crop_path text,
  content_digest text,
  metadata_embedding extensions.vector(256),
  updated_at timestamptz not null default now(),
  primary key (owner_id, record_id),
  unique (owner_id, scan_id, garment_id)
);

create index if not exists stylezam_library_garments_owner_created_idx
on public.stylezam_library_garments (owner_id, created_at desc);
create index if not exists stylezam_library_garments_owner_category_idx
on public.stylezam_library_garments (owner_id, category);
create index if not exists stylezam_library_garments_embedding_idx
on public.stylezam_library_garments
using hnsw (metadata_embedding vector_cosine_ops);

create table if not exists public.stylezam_library_wardrobe (
  record_id uuid not null,
  owner_id text not null,
  saved_at timestamptz not null,
  title text not null,
  category text not null,
  crop_path text,
  content_digest text,
  source_scan_id uuid,
  source_garment_id text,
  source_product jsonb,
  updated_at timestamptz not null default now(),
  primary key (owner_id, record_id)
);

create table if not exists public.stylezam_library_searches (
  record_id text not null,
  owner_id text not null,
  scan_id uuid not null,
  garment_id text not null,
  created_at timestamptz not null,
  pipeline text not null,
  provider_summary text not null,
  generated_query text,
  result_count integer not null,
  results jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, record_id)
);

create table if not exists public.stylezam_library_products (
  record_id text not null,
  owner_id text not null,
  saved_at timestamptz not null,
  product jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, record_id)
);

create table if not exists public.stylezam_library_chats (
  record_id text not null,
  owner_id text not null,
  scan_id uuid not null,
  garment_id text not null,
  messages jsonb not null,
  updated_at timestamptz not null,
  primary key (owner_id, record_id)
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'stylezam_library_garments',
    'stylezam_library_wardrobe',
    'stylezam_library_searches',
    'stylezam_library_products',
    'stylezam_library_chats'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy "owners manage %1$s" on public.%1$I for all to authenticated using (owner_id = public.stylezam_current_owner()) with check (owner_id = public.stylezam_current_owner())',
      table_name
    );
  end loop;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'stylezam-private-library',
  'stylezam-private-library',
  false,
  6291456,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.stylezam_can_store_private_object(
  object_name text,
  object_bytes bigint
)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  with requested as (
    select (storage.foldername(object_name))[1] as owner_id
  ), allowance as (
    select coalesce(
      (select quota_bytes from public.stylezam_cloud_entitlements e
       where e.owner_id = (select owner_id from requested)),
      262144000
    ) as quota_bytes
  ), current_usage as (
    select coalesce(sum((o.metadata ->> 'size')::bigint), 0) as used_bytes
    from storage.objects o
    where o.bucket_id = 'stylezam-private-library'
      and (storage.foldername(o.name))[1] = (select owner_id from requested)
      and o.name <> object_name
  )
  select (select owner_id from requested) = public.stylezam_current_owner()
    and (select used_bytes from current_usage) + greatest(object_bytes, 0)
      <= (select quota_bytes from allowance);
$$;

revoke all on function public.stylezam_can_store_private_object(text, bigint) from public;
grant execute on function public.stylezam_can_store_private_object(text, bigint) to authenticated;

create policy "owners read private Stylezam crops"
on storage.objects for select to authenticated
using (
  bucket_id = 'stylezam-private-library'
  and (storage.foldername(name))[1] = public.stylezam_current_owner()
);

create policy "owners upload private Stylezam crops"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'stylezam-private-library'
  and (storage.foldername(name))[1] = public.stylezam_current_owner()
  and public.stylezam_can_store_private_object(
    name,
    coalesce((metadata ->> 'size')::bigint, 0)
  )
);

create policy "owners update private Stylezam crops"
on storage.objects for update to authenticated
using (
  bucket_id = 'stylezam-private-library'
  and (storage.foldername(name))[1] = public.stylezam_current_owner()
)
with check (
  bucket_id = 'stylezam-private-library'
  and (storage.foldername(name))[1] = public.stylezam_current_owner()
  and public.stylezam_can_store_private_object(
    name,
    coalesce((metadata ->> 'size')::bigint, 0)
  )
);

create policy "owners delete private Stylezam crops"
on storage.objects for delete to authenticated
using (
  bucket_id = 'stylezam-private-library'
  and (storage.foldername(name))[1] = public.stylezam_current_owner()
);

create or replace function public.stylezam_match_library_garments(
  query_embedding extensions.vector(256),
  match_count integer default 4
)
returns table (
  record_id text,
  scan_id uuid,
  garment_id text,
  title text,
  category text,
  crop_path text,
  similarity double precision
)
language sql
stable
security invoker
as $$
  select
    g.record_id,
    g.scan_id,
    g.garment_id,
    g.title,
    g.category,
    g.crop_path,
    1 - (g.metadata_embedding <=> query_embedding) as similarity
  from public.stylezam_library_garments g
  where g.owner_id = public.stylezam_current_owner()
    and g.accepted
    and g.metadata_embedding is not null
  order by g.metadata_embedding <=> query_embedding
  limit greatest(1, least(match_count, 8));
$$;

grant execute on function public.stylezam_match_library_garments(extensions.vector, integer)
to authenticated;

create or replace function public.stylezam_cloud_usage_bytes()
returns bigint
language sql
stable
security invoker
as $$
  select coalesce(sum((metadata ->> 'size')::bigint), 0)
  from storage.objects
  where bucket_id = 'stylezam-private-library'
    and (storage.foldername(name))[1] = public.stylezam_current_owner();
$$;

grant execute on function public.stylezam_cloud_usage_bytes() to authenticated;
