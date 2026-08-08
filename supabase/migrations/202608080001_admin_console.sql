-- YePly Admin: privileged operations exposed through guarded RPCs.
-- Execute after 202608070001_initial.sql.

create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role public.user_role
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'admin_required' using errcode = '42501';
  end if;

  if p_user_id = auth.uid() and p_role <> 'admin'::public.user_role then
    raise exception 'cannot_demote_current_admin' using errcode = '42501';
  end if;

  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
    || jsonb_build_object('role', p_role::text)
  where id = p_user_id;

  update public.profiles
  set role = p_role, updated_at = now()
  where id = p_user_id;

  insert into public.audit_log(actor_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'user_role_changed',
    'profile',
    p_user_id,
    jsonb_build_object('role', p_role::text)
  );
end;
$$;

revoke all on function public.admin_set_user_role(uuid, public.user_role) from public;
grant execute on function public.admin_set_user_role(uuid, public.user_role) to authenticated;

comment on function public.admin_set_user_role(uuid, public.user_role)
is 'Changes a user role in both the profile and Auth app_metadata. Only an authenticated admin may execute it.';
