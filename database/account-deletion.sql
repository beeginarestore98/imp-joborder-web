-- Remove login identities permanently; retain anonymous actor IDs for job/audit FKs.
create table public.impjo_account_deletions(
 principal_id uuid primary key references public.impjo_principals(id),
 auth_user_id uuid, requested_by uuid not null references public.impjo_principals(id),
 requested_at timestamptz not null default now(),completed_at timestamptz
);
create unique index impjo_deleting_auth_user on public.impjo_account_deletions(auth_user_id) where auth_user_id is not null;
alter table public.impjo_account_deletions enable row level security;
revoke all on public.impjo_account_deletions from public,anon,authenticated;
grant all on public.impjo_account_deletions to service_role;

create function public.impjo_account_admin(p_actor uuid,p_action text,p_target uuid default null) returns jsonb
language plpgsql set search_path='' as $$
declare person public.impjo_principals; target public.impjo_principals; deletion public.impjo_account_deletions; uid uuid;result jsonb;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if person.id is null or person.kind<>'STAFF' or person.state<>'APPROVED' or person.archived_at is not null
  or not exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='list' then
  return jsonb_build_object('people',coalesce((select jsonb_agg(to_jsonb(x)) from(
   select p.id,p.name,p.kind,(d.principal_id is not null) as deletion_pending from public.impjo_principals p
   left join public.impjo_account_deletions d on d.principal_id=p.id
   where p.archived_at is not null and d.completed_at is null order by p.archived_at desc limit 200
  )x),'[]'));
 end if;
 if p_action='confirmation' then
  select jsonb_build_object('id',p.id,'name',p.name,'state',p.state,'roles',coalesce((select jsonb_agg(role order by role) from public.impjo_roles where principal_id=p.id),'[]')) into result
   from public.impjo_principals p where id=p_target and archived_at is null;
  if result is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  return result;
 end if;
 if p_target=p_actor then raise exception 'CANNOT_CHANGE_SELF' using errcode='42501';end if;
 select * into target from public.impjo_principals where id=p_target for update;
 if target.id is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 select * into deletion from public.impjo_account_deletions where principal_id=p_target;
 if p_action='prepare' then
  if deletion.principal_id is not null then return jsonb_build_object('auth_user_id',deletion.auth_user_id,'completed',deletion.completed_at is not null);end if;
  select auth_user_id into uid from public.impjo_staff_identities where principal_id=p_target;
  if uid is not null then perform pg_advisory_xact_lock(hashtextextended(uid::text,0));end if;
  perform impjo_private.revoke_staff_sessions(p_actor,p_target);
  insert into public.impjo_account_deletions(principal_id,auth_user_id,requested_by) values(p_target,uid,p_actor);
  update public.impjo_principals set state='DISABLED',archived_at=coalesce(archived_at,now()),archived_by=p_actor where id=p_target;
  delete from public.impjo_roles where principal_id=p_target;
  delete from public.impjo_sessions where principal_id=p_target;
  delete from public.impjo_staff_line_links where staff_id=p_target or line_id=p_target;
  delete from public.impjo_staff_link_codes where staff_id=p_target;
  delete from public.impjo_staff_identities where principal_id=p_target;
  delete from public.impjo_line_identities where principal_id=p_target;
  delete from public.impjo_report_recipients where recipient_id=p_target;
  update public.impjo_assignments set revoked_at=now() where principal_id=p_target and revoked_at is null;
  update public.impjo_invitations set revoked_at=now(),revoked_by=p_actor where created_by=p_target and revoked_at is null;
  insert into public.impjo_events(actor_id,action,target_id) values(p_actor,'ACCOUNT_DELETE_STARTED',p_target);
  return jsonb_build_object('auth_user_id',uid,'completed',false);
 elsif p_action='finish' then
  if deletion.principal_id is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  if deletion.completed_at is not null then return jsonb_build_object('ok',true);end if;
  -- A staff deletion can be finalized only after Auth confirms the user is gone.
  if deletion.auth_user_id is not null and exists(select 1 from impjo_private.staff_auth(deletion.auth_user_id)) then raise exception 'ACCOUNT_DELETE_PENDING';end if;
  update public.impjo_principals set name='บัญชีที่ลบแล้ว',state='DISABLED' where id=p_target;
  update public.impjo_account_deletions set completed_at=now(),auth_user_id=null where principal_id=p_target;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'ACCOUNT_DELETED',p_target,'Login identities removed permanently; anonymous job/audit references retained');
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function public.impjo_account_admin(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.impjo_account_admin(uuid,text,uuid) to service_role;

do $migration$
declare definition text;needle text;
begin
 -- A failed Auth deletion cannot be bypassed using an old JWT or duplicate signup.
 foreach needle in array array['public.impjo_staff_actor(uuid)','public.impjo_register_pending(uuid)'] loop
  definition:=pg_get_functiondef(needle::regprocedure);
  if strpos(definition,'select principal_id into')=0 then raise exception 'Unexpected staff bridge';end if;
  definition:=replace(definition,'select principal_id into',E'if exists(select 1 from public.impjo_account_deletions where auth_user_id=p_uid) then raise exception ''AUTH_REQUIRED'' using errcode=''28000'';end if;\n select principal_id into');
  execute definition;
 end loop;
 definition:=pg_get_functiondef('public.impjo_manage(uuid,text,jsonb)'::regprocedure);
 needle:='if p_action=''archive_account'' then';
 if strpos(definition,needle)=0 then raise exception 'Unexpected account management';end if;
 definition:=replace(definition,needle,'if exists(select 1 from public.impjo_account_deletions where principal_id=target.id) then raise exception ''ACCOUNT_DELETED'' using errcode=''42501'';end if; '||needle);
 -- Permanently deleted actors are never offered for restoration by old clients.
 definition:=replace(definition,'from public.impjo_principals where archived_at is not null','from public.impjo_principals where archived_at is not null and not exists(select 1 from public.impjo_account_deletions d where d.principal_id=impjo_principals.id)');
 execute definition;
end $migration$;

