begin;
create function public.impjo_staff_session_actor(p_uid uuid,p_session uuid) returns uuid language plpgsql set search_path='' as $$
begin
 if not exists(select 1 from auth.sessions where id=p_session and user_id=p_uid and (not_after is null or not_after>now())) then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 return public.impjo_staff_actor(p_uid);
end $$;
revoke all on function public.impjo_staff_session_actor(uuid,uuid) from public,anon,authenticated;
grant execute on function public.impjo_staff_session_actor(uuid,uuid) to service_role;
commit;
