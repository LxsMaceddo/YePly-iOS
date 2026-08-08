-- Run only from the trusted Supabase SQL editor. Replace the email first.
do $$
declare target_id uuid;
begin
  select id into target_id from auth.users where lower(email) = lower('SEU_EMAIL@EXEMPLO.COM') limit 1;
  if target_id is null then raise exception 'User not found'; end if;
  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
  where id = target_id;
  update public.profiles set role = 'admin' where id = target_id;
end $$;
