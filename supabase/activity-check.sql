-- Lightweight API activity check for Supabase's Free plan.
-- This function returns no family data and performs no writes.
create or replace function public.activity_check()
returns boolean
language sql
volatile
security invoker
set search_path = ''
as $$
  select clock_timestamp() is not null;
$$;

revoke all on function public.activity_check() from public, anon, authenticated;
grant execute on function public.activity_check() to anon, authenticated;
notify pgrst, 'reload schema';
