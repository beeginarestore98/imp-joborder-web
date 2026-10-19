begin;
create schema impjo_private;
revoke all on schema impjo_private from public,anon,authenticated;
grant usage on schema impjo_private to service_role;
create function impjo_private.staff_auth(p_uid uuid) returns table(email text,confirmed boolean,banned boolean)
language sql stable security definer set search_path='' as $$
 select u.email,u.email_confirmed_at is not null,coalesce(u.banned_until>now(),false) from auth.users u where u.id=p_uid
$$;
create function impjo_private.session_active(p_uid uuid,p_session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions where id=p_session and user_id=p_uid and (not_after is null or not_after>now()))
$$;
revoke all on function impjo_private.staff_auth(uuid),impjo_private.session_active(uuid,uuid) from public,anon,authenticated;
grant execute on function impjo_private.staff_auth(uuid),impjo_private.session_active(uuid,uuid) to service_role;
create or replace function public.impjo_staff_actor(p_uid uuid) returns uuid language plpgsql set search_path='' as $$
declare v_actor uuid; v_email text; v_confirmed boolean; v_banned boolean;
begin
 select email,confirmed,banned into v_email,v_confirmed,v_banned from impjo_private.staff_auth(p_uid);
 if v_email is null or not v_confirmed or v_banned then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_uid::text,0));
 select principal_id into v_actor from public.impjo_staff_identities where auth_user_id=p_uid;
 if v_actor is null then
  insert into public.impjo_principals(kind,name) values('STAFF',v_email) returning id into v_actor;
  insert into public.impjo_staff_identities values(p_uid,v_actor);
  -- Bootstrap only the specifically authorized verified email. No user metadata is trusted.
  if lower(v_email)='__VERIFIED_BOOTSTRAP_ADMIN_EMAIL__' then
   update public.impjo_principals set state='APPROVED' where id=v_actor;
   insert into public.impjo_roles values(v_actor,'ADMIN');
   insert into public.impjo_events(actor_id,action,target_id) values(v_actor,'BOOTSTRAP_ADMIN',v_actor);
  end if;
 end if;
 return v_actor;
end $$;

create or replace function public.impjo_staff_session_actor(p_uid uuid,p_session uuid) returns uuid language plpgsql set search_path='' as $$
begin
 if not impjo_private.session_active(p_uid,p_session) then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 return public.impjo_staff_actor(p_uid);
end $$;
revoke all on function public.impjo_staff_actor(uuid),public.impjo_staff_session_actor(uuid,uuid) from public,anon,authenticated;
grant execute on function public.impjo_staff_actor(uuid),public.impjo_staff_session_actor(uuid,uuid) to service_role;
commit;

