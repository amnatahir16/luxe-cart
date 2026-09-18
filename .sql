-- ============================================================================
-- LuxeCart — Supabase schema
-- Run this whole file once in your Supabase project's SQL Editor
-- (Project -> SQL Editor -> New query -> paste -> Run)
-- ============================================================================

-- 1. Profiles: one row per signed-up user, created automatically on signup
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  created_at timestamptz default now()
);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email);
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2. Contact form submissions
create table if not exists public.contact_messages (
  id bigint generated always as identity primary key,
  name text not null,
  email text not null,
  topic text,
  message text not null,
  created_at timestamptz default now()
);

-- 3. Orders placed at checkout
create table if not exists public.orders (
  id bigint generated always as identity primary key,
  order_number text unique not null,
  user_id uuid references auth.users(id),
  customer_name text not null,
  customer_email text not null,
  customer_phone text,
  address text,
  city text,
  postal_code text,
  payment_method text,
  subtotal numeric,
  discount numeric,
  shipping numeric,
  total numeric,
  status text default 'pending',
  created_at timestamptz default now()
);

-- 4. Line items for each order
create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id bigint references public.orders(id) on delete cascade,
  product_id integer,
  product_name text,
  qty integer,
  price numeric
);

-- ============================================================================
-- Row Level Security
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.contact_messages enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- Profiles: users can see/update only their own row
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id);

-- Contact messages: anyone (including guests) can submit; nobody can read from the client
drop policy if exists "Anyone can submit a contact message" on public.contact_messages;
create policy "Anyone can submit a contact message"
  on public.contact_messages for insert
  to anon, authenticated
  with check (true);

-- Orders: anyone can place one (guest checkout allowed); users can view their own past orders
drop policy if exists "Anyone can place an order" on public.orders;
create policy "Anyone can place an order"
  on public.orders for insert
  to anon, authenticated
  with check (true);

drop policy if exists "Users can view their own orders" on public.orders;
create policy "Users can view their own orders"
  on public.orders for select
  to authenticated
  using (auth.uid() = user_id);

-- Order items: anyone can insert (as part of placing an order); users can view items on their own orders
drop policy if exists "Anyone can insert order items" on public.order_items;
create policy "Anyone can insert order items"
  on public.order_items for insert
  to anon, authenticated
  with check (true);

drop policy if exists "Users can view their own order items" on public.order_items;
create policy "Users can view their own order items"
  on public.order_items for select
  to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id and o.user_id = auth.uid()
    )
  );

-- ============================================================================
-- Done. To view submissions/orders as the store owner, use the Supabase
-- Table Editor (Table Editor -> contact_messages / orders / order_items) —
-- the dashboard uses your service role and bypasses RLS automatically.
-- ============================================================================
