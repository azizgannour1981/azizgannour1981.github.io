-- SECURE_SCHEMA.sql
-- برنامج مراقبة كتابة النيابة العامة — الإصدار المؤسسي 1.3
-- ينفذ مرة واحدة في Supabase SQL Editor.

create table if not exists public.allowed_users (
  email text primary key,
  full_name text,
  active boolean not null default true,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  constraint allowed_users_role_chk check (role in ('admin','member'))
);

alter table public.allowed_users add column if not exists role text not null default 'member';
alter table public.allowed_users add column if not exists created_at timestamptz not null default now();

insert into public.allowed_users(email,full_name,active,role)
values ('azizgannour@gmail.com','مدير البرنامج',true,'admin')
on conflict (email) do update set full_name=excluded.full_name, active=true, role='admin';

alter table public.allowed_users enable row level security;

-- منع الوصول المباشر إلا للمستخدم الإداري الحالي.
drop policy if exists allowed_users_admin_select on public.allowed_users;
drop policy if exists allowed_users_admin_insert on public.allowed_users;
drop policy if exists allowed_users_admin_update on public.allowed_users;
drop policy if exists allowed_users_admin_delete on public.allowed_users;

create or replace function public.is_current_user_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.allowed_users
    where lower(email)=lower(coalesce(auth.email(),''))
      and active=true and role='admin'
  );
$$;

create or replace function public.is_current_user_allowed()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.allowed_users
    where lower(email)=lower(coalesce(auth.email(),''))
      and active=true
  );
$$;

-- توافق مع النسخ السابقة: لا يسمح بفحص بريد عشوائي؛ يتم الاعتماد على جلسة المستخدم الحالية.
create or replace function public.is_email_allowed(p_email text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.is_current_user_allowed() and lower(coalesce(p_email,''))=lower(coalesce(auth.email(),''));
$$;

revoke all on function public.is_current_user_admin() from public;
revoke all on function public.is_current_user_allowed() from public;
revoke all on function public.is_email_allowed(text) from public;
grant execute on function public.is_current_user_admin() to authenticated;
grant execute on function public.is_current_user_allowed() to authenticated;
grant execute on function public.is_email_allowed(text) to authenticated;

create policy allowed_users_admin_select on public.allowed_users
for select to authenticated using (public.is_current_user_admin());
create policy allowed_users_admin_insert on public.allowed_users
for insert to authenticated with check (public.is_current_user_admin());
create policy allowed_users_admin_update on public.allowed_users
for update to authenticated using (public.is_current_user_admin()) with check (public.is_current_user_admin());
create policy allowed_users_admin_delete on public.allowed_users
for delete to authenticated using (public.is_current_user_admin());

-- مستودع التقارير خاص.
insert into storage.buckets (id,name,public)
values ('reports','reports',false)
on conflict (id) do update set public=false;

drop policy if exists reports_authenticated_select on storage.objects;
create policy reports_authenticated_select on storage.objects
for select to authenticated
using (bucket_id='reports' and public.is_current_user_allowed());

-- لا تمنح واجهة المستخدم صلاحية رفع/حذف التقارير؛ تظل إدارة التقارير من Storage.
