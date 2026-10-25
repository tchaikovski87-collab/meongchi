-- 멍치과 예약 시스템 스키마
-- Supabase 대시보드 > SQL Editor 에 통째로 붙여넣고 Run 하세요.

create extension if not exists pgcrypto;

-- 1) 예약 테이블 -------------------------------------------------------------
create table if not exists public.bookings (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  hospital_id   text not null check (char_length(hospital_id) <= 40),
  hospital_name text not null check (char_length(hospital_name) <= 100),
  owner_name    text not null check (char_length(owner_name) between 1 and 50),
  phone         text not null check (phone ~ '^[0-9+() -]{9,20}$'),
  dog_name      text not null check (char_length(dog_name) between 1 and 50),
  breed         text check (char_length(breed) <= 50),
  age           numeric check (age >= 0 and age <= 30),
  weight        numeric check (weight > 0 and weight <= 100),
  visit_date    date not null,
  time_slot     text not null check (time_slot in ('오전','오후','상관없음')),
  memo          text check (char_length(memo) <= 1000),
  status        text not null default '대기' check (status in ('대기','확정','취소','완료')),
  admin_note    text check (char_length(admin_note) <= 1000)
);

create index if not exists bookings_visit_date_idx on public.bookings (visit_date);
create index if not exists bookings_status_idx on public.bookings (status);

-- 2) 관리자 목록 -------------------------------------------------------------
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

-- 3) 관리자 판별 함수 --------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- 4) updated_at 자동 갱신 ----------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists bookings_touch on public.bookings;
create trigger bookings_touch before update on public.bookings
for each row execute function public.touch_updated_at();

-- 5) 행 단위 보안(RLS) -------------------------------------------------------
alter table public.bookings enable row level security;
alter table public.admins   enable row level security;

drop policy if exists "visitors can submit"   on public.bookings;
drop policy if exists "admins can read"       on public.bookings;
drop policy if exists "admins can update"     on public.bookings;
drop policy if exists "admins can delete"     on public.bookings;
drop policy if exists "admin sees own row"    on public.admins;

-- 누구나 '대기' 상태의 새 예약만 넣을 수 있음 (조회·수정 불가)
create policy "visitors can submit" on public.bookings
  for insert to anon, authenticated
  with check (status = '대기' and admin_note is null and visit_date >= current_date);

-- 관리자만 조회·수정·삭제
create policy "admins can read" on public.bookings
  for select to authenticated using (public.is_admin());
create policy "admins can update" on public.bookings
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins can delete" on public.bookings
  for delete to authenticated using (public.is_admin());

create policy "admin sees own row" on public.admins
  for select to authenticated using (user_id = auth.uid());

-- 6) 관리자 등록 (Authentication 에서 사용자를 만든 뒤 이메일을 바꿔 실행) -----
-- insert into public.admins (user_id)
-- select id from auth.users where email = 'admin@example.com';

-- 7) (선택) 진료일이 6개월 지난 예약 삭제 — 동의 문구와 맞추려면 주기적으로 실행
-- delete from public.bookings where visit_date < current_date - interval '6 months';
