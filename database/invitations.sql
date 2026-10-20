-- Reusable, role-bound invitations. Raw bearer tokens never enter the database.
create table public.impjo_invitations (
 id uuid primary key default gen_random_uuid(), token_hash text not null unique check(token_hash ~ '^[0-9a-f]{64}$'),
 label text not null check(length(btrim(label)) between 1 and 120),
 kind text not null check(kind in ('STAFF','LINE')), role text not null,
 created_by uuid not null references public.impjo_principals(id), created_at timestamptz not null default now(),
 revoked_at timestamptz, revoked_by uuid references public.impjo_principals(id),
 check((kind='STAFF' and role in ('ADMIN','OPERATOR')) or (kind='LINE' and role in ('OPERATOR','OUTSOURCE','MESS')))
);
create table public.impjo_invitation_uses (
 invitation_id uuid not null references public.impjo_invitations(id),
 principal_id uuid not null references public.impjo_principals(id), used_at timestamptz not null default now(),
 primary key(invitation_id,principal_id)
);
create index impjo_invitation_uses_actor on public.impjo_invitation_uses(principal_id);
alter table public.impjo_invitations enable row level security;
alter table public.impjo_invitation_uses enable row level security;
revoke all on public.impjo_invitations,public.impjo_invitation_uses from public,anon,authenticated;
grant all on public.impjo_invitations,public.impjo_invitation_uses to service_role;

create function public.impjo_invite(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql set search_path='' as $$
declare person public.impjo_principals; invitation public.impjo_invitations; v_id uuid; v_hash text; v_role text; v_kind text; result jsonb;
begin
 if p_action in ('inspect','redeem') then
  v_hash:=p_data->>'hash';
  if v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then raise exception 'INVITE_UNAVAILABLE' using errcode='P0002';end if;
  -- Serialize redemption with revocation; never trust the browser's role or identity kind.
  select * into invitation from public.impjo_invitations where token_hash=v_hash for update;
  if invitation.id is null or invitation.revoked_at is not null then raise exception 'INVITE_UNAVAILABLE' using errcode='P0002';end if;
  perform 1 from public.impjo_principals p where p.id=invitation.created_by and p.kind='STAFF' and p.state='APPROVED' and p.archived_at is null
   and exists(select 1 from public.impjo_roles r where r.principal_id=p.id and r.role='ADMIN') for share;
  if not found then raise exception 'INVITE_UNAVAILABLE' using errcode='P0002';end if;
  if p_action='inspect' then return jsonb_build_object('label',invitation.label,'kind',invitation.kind,'role',invitation.role);end if;
  select * into person from public.impjo_principals where id=p_actor for update;
  if person.id is null or person.archived_at is not null or person.state not in ('PENDING','APPROVED') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  if person.kind<>invitation.kind then raise exception 'INVITE_WRONG_ACCOUNT' using errcode='42501';end if;
  if person.kind='STAFF' then
   -- The authenticated gateway already checks Auth's confirmed email and active session.
   if not exists(select 1 from public.impjo_staff_identities where principal_id=p_actor) then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  elsif not exists(select 1 from public.impjo_line_identities where principal_id=p_actor) then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
  if person.state='APPROVED' then
   if exists(select 1 from public.impjo_invitation_uses where invitation_id=invitation.id and principal_id=p_actor)
    and exists(select 1 from public.impjo_roles where principal_id=p_actor and role=invitation.role)
    then return jsonb_build_object('ok',true,'already_joined',true);end if;
   raise exception 'INVITE_ACCOUNT_HAS_ROLE' using errcode='42501';
  end if;
  if exists(select 1 from public.impjo_roles where principal_id=p_actor) then raise exception 'INVITE_ACCOUNT_HAS_ROLE' using errcode='42501';end if;
  update public.impjo_principals set state='APPROVED' where id=p_actor;
  insert into public.impjo_roles(principal_id,role) values(p_actor,invitation.role);
  insert into public.impjo_invitation_uses(invitation_id,principal_id) values(invitation.id,p_actor);
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'INVITATION_REDEEMED',invitation.id,jsonb_build_object('role',invitation.role,'kind',invitation.kind,'invited_by',invitation.created_by)::text);
  return jsonb_build_object('ok',true,'role',invitation.role);
 end if;
 select * into person from public.impjo_principals where id=p_actor for share;
 if person.id is null or person.kind<>'STAFF' or person.state<>'APPROVED' or person.archived_at is not null
  or not exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='list' then
  select coalesce(jsonb_agg(x order by x.created_at desc),'[]') into result from (
   select i.id,i.label,i.kind,i.role,i.created_at,i.revoked_at,
    (i.revoked_at is null and c.state='APPROVED' and c.archived_at is null and exists(select 1 from public.impjo_roles where principal_id=c.id and role='ADMIN')) as active,
    (select count(*) from public.impjo_invitation_uses u where u.invitation_id=i.id) as uses
   from public.impjo_invitations i join public.impjo_principals c on c.id=i.created_by order by i.created_at desc limit 200
  ) x;
  return jsonb_build_object('invitations',result);
 elsif p_action='create' then
  v_hash:=p_data->>'hash';v_role:=p_data->>'role';v_kind:=p_data->>'kind';
  if v_hash is null or v_hash !~ '^[0-9a-f]{64}$' or coalesce(length(btrim(p_data->>'label')),0) not between 1 and 120
   or not coalesce((v_kind='STAFF' and v_role in ('ADMIN','OPERATOR')) or (v_kind='LINE' and v_role in ('OPERATOR','OUTSOURCE','MESS')),false)
   then raise exception 'INVALID_INVITE';end if;
  insert into public.impjo_invitations(token_hash,label,kind,role,created_by) values(v_hash,btrim(p_data->>'label'),v_kind,v_role,p_actor) returning id into v_id;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'INVITATION_CREATED',v_id,jsonb_build_object('role',v_role,'kind',v_kind,'label',p_data->>'label')::text);
  return jsonb_build_object('id',v_id);
 elsif p_action='revoke' then
  update public.impjo_invitations set revoked_at=now(),revoked_by=p_actor where id=(p_data->>'id')::uuid and revoked_at is null returning id into v_id;
  if v_id is not null then insert into public.impjo_events(actor_id,action,target_id) values(p_actor,'INVITATION_REVOKED',v_id);end if;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION';
end $$;
revoke all on function public.impjo_invite(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_invite(uuid,text,jsonb) to service_role;

