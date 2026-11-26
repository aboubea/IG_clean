/** Schéma Postgres. Idempotent : rejoué à chaque démarrage. */
export const SCHEMA = /* sql */ `
create table if not exists users (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  display_name text,
  profile_type text not null default 'curious' check (profile_type in ('creator', 'business', 'curious')),
  goal text not null default 'awareness' check (goal in ('awareness', 'engagement', 'traffic', 'sales')),
  timezone text not null default 'Europe/Paris',
  plan text not null default 'free' check (plan in ('free', 'premium')),
  premium_until timestamptz,
  referral_code text not null unique,
  referred_by uuid references users (id) on delete set null,
  public_slug text unique,
  media_kit_public boolean not null default false
);

create table if not exists sessions (
  token_hash text primary key,
  user_id uuid not null references users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists oauth_states (
  state text primary key,
  user_id uuid not null references users (id) on delete cascade,
  network text not null,
  created_at timestamptz not null default now()
);

create table if not exists connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  network text not null check (network in ('instagram', 'facebook', 'tiktok', 'linkedin')),
  mode text not null check (mode in ('official', 'demo')),
  external_id text not null,
  handle text not null,
  display_name text,
  avatar_url text,
  credentials text,
  status text not null default 'active',
  last_synced_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  unique (user_id, network)
);

create table if not exists account_daily (
  connection_id uuid not null references connections (id) on delete cascade,
  day date not null,
  followers integer not null,
  reach integer,
  impressions integer,
  profile_views integer,
  primary key (connection_id, day)
);

create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references connections (id) on delete cascade,
  external_id text not null,
  format text not null,
  caption text not null default '',
  permalink text,
  thumbnail_url text,
  published_at timestamptz not null,
  views integer,
  reach integer,
  likes integer not null default 0,
  comments integer not null default 0,
  shares integer not null default 0,
  saves integer not null default 0,
  metrics_updated_at timestamptz not null default now(),
  unique (connection_id, external_id)
);
create index if not exists posts_by_connection on posts (connection_id, published_at desc);

create table if not exists ai_usage (
  user_id uuid not null references users (id) on delete cascade,
  feature text not null,
  week_start date not null,
  count integer not null default 0,
  primary key (user_id, feature, week_start)
);

create table if not exists recaps (
  user_id uuid not null references users (id) on delete cascade,
  week_start date not null,
  payload jsonb not null,
  source text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, week_start)
);

create table if not exists coach_messages (
  id bigserial primary key,
  user_id uuid not null references users (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);
create index if not exists coach_by_user on coach_messages (user_id, id);

create table if not exists brand_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  brand text not null,
  email text not null,
  message text not null,
  budget text,
  status text not null default 'new',
  created_at timestamptz not null default now()
);
`;
