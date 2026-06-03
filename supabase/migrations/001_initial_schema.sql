-- ============================================================
-- Personal English OS — Initial Schema
-- Run in Supabase SQL Editor
-- ============================================================

-- Enable pgcrypto for uuid generation
create extension if not exists "pgcrypto";

-- ============================================================
-- profiles (extends auth.users)
-- ============================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles: owner access"
  on public.profiles for all to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.profiles to service_role;

-- Auto-create profile on sign-up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- sessions (chat / journal / youtube sessions)
-- ============================================================
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type text not null check (source_type in ('chat', 'journal', 'youtube')),
  title text,
  status text not null default 'active'
    check (status in ('active', 'ended', 'analyzing', 'analyzed', 'error')),
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index sessions_user_id_idx on public.sessions (user_id, created_at desc);

alter table public.sessions enable row level security;

create policy "sessions: owner access"
  on public.sessions for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.sessions to authenticated;
grant select, insert, update, delete on public.sessions to service_role;

-- ============================================================
-- messages (chat messages within a session)
-- ============================================================
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create index messages_session_id_idx on public.messages (session_id, created_at asc);

alter table public.messages enable row level security;

create policy "messages: owner access"
  on public.messages for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.messages to service_role;

-- ============================================================
-- quiz_cards (1 Unified Output — the core table)
-- ============================================================
create table public.quiz_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete set null,
  source_type text not null check (source_type in ('chat', 'journal', 'youtube')),
  card_type text not null check (card_type in ('sentence', 'word', 'phrase')),
  save_mode text not null check (save_mode in ('auto', 'manual')),
  error_category text check (error_category in ('grammar', 'unnatural', 'vocab', null)),

  -- Core content
  original_text text not null,
  corrected_text text,
  nuance_explanation text,
  context_snippet text,

  -- Rich background knowledge (jsonb)
  alternative_examples jsonb default '[]'::jsonb,  -- string[]
  synonyms jsonb default '[]'::jsonb,               -- [{expr, note}]
  confusable_with jsonb default '[]'::jsonb,        -- [{expr, difference}]
  homonyms jsonb default '[]'::jsonb,               -- [{word, meaning}]
  collocations jsonb default '[]'::jsonb,           -- string[]
  register text check (register in ('formal', 'neutral', 'casual', 'slang', null)),

  -- Enrich processing state
  enrich_status text not null default 'pending'
    check (enrich_status in ('pending', 'core', 'full', 'failed')),

  -- Deduplication
  dedup_key text not null,
  reinforce_count int not null default 0,

  -- SM-2 Spaced Repetition
  ease_factor real not null default 2.5,
  interval_days int not null default 0,
  repetitions int not null default 0,
  next_review_at timestamptz not null default now(),
  last_reviewed_at timestamptz,

  created_at timestamptz not null default now()
);

-- Unique constraint for deduplication per user
create unique index quiz_cards_dedup_idx on public.quiz_cards (user_id, dedup_key);

-- Composite index for review queue
create index quiz_cards_review_queue_idx on public.quiz_cards (user_id, next_review_at asc)
  where enrich_status != 'pending';

create index quiz_cards_source_idx on public.quiz_cards (user_id, source_type, created_at desc);

alter table public.quiz_cards enable row level security;

create policy "quiz_cards: owner access"
  on public.quiz_cards for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.quiz_cards to authenticated;
grant select, insert, update, delete on public.quiz_cards to service_role;

-- ============================================================
-- articles (Module B — Journal Reader, Phase 2)
-- ============================================================
create table public.articles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_subscription_id uuid,  -- fk added after feed_subscriptions
  source_url text,
  title text,
  author text,
  clean_text text,
  read_status text not null default 'unread'
    check (read_status in ('unread', 'reading', 'completed')),
  fetched_at timestamptz not null default now(),
  published_at timestamptz
);

create index articles_user_id_idx on public.articles (user_id, fetched_at desc);

alter table public.articles enable row level security;

create policy "articles: owner access"
  on public.articles for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.articles to authenticated;
grant select, insert, update, delete on public.articles to service_role;

-- ============================================================
-- feed_subscriptions (Module B — RSS subscriptions, Phase 2)
-- ============================================================
create table public.feed_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feed_url text not null,
  title text,
  last_polled_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index feed_subscriptions_unique_idx on public.feed_subscriptions (user_id, feed_url);

alter table public.feed_subscriptions enable row level security;

create policy "feed_subscriptions: owner access"
  on public.feed_subscriptions for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update, delete on public.feed_subscriptions to authenticated;
grant select, insert, update, delete on public.feed_subscriptions to service_role;

-- Add FK from articles to feed_subscriptions
alter table public.articles
  add constraint articles_feed_subscription_id_fkey
  foreign key (feed_subscription_id)
  references public.feed_subscriptions(id)
  on delete set null;

-- ============================================================
-- PowerSync replication setup
-- Run once per project
-- ============================================================

-- Create PowerSync replication user
-- (Replace 'your_secure_password' before running)
-- CREATE ROLE powersync_role WITH REPLICATION BYPASSRLS LOGIN PASSWORD 'your_secure_password';
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO powersync_role;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO powersync_role;

-- Create publication for PowerSync
-- CREATE PUBLICATION powersync FOR ALL TABLES;
