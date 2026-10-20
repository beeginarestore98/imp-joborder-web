-- Service-role-only account linking. Raw codes are never stored.
create table public.impjo_staff_link_codes(
 token_hash text primary key check(length(token_hash)=64),
 staff_id uuid not null references public.impjo_principals(id),
 expires_at timestamptz not null default now()+interval '10 minutes',
 used_at timestamptz,created_at timestamptz not null default now());
create table public.impjo_staff_line_links(
 id uuid primary key default gen_random_uuid(),
 line_id uuid not null references public.impjo_principals(id),
 staff_id uuid not null references public.impjo_principals(id),
 state text not null default 'PENDING' check(state in ('PENDING','APPROVED','REVOKED')),
 approved_by uuid references public.impjo_principals(id),
 approved_at timestamptz,created_at timestamptz not null default now());
create unique index impjo_one_active_line_link on public.impjo_staff_line_links(line_id) where state<>'REVOKED';
create unique index impjo_one_active_staff_link on public.impjo_staff_line_links(staff_id) where state<>'REVOKED';
alter table public.impjo_staff_link_codes enable row level security;
alter table public.impjo_staff_line_links enable row level security;
revoke all on public.impjo_staff_link_codes,public.impjo_staff_line_links from public,anon,authenticated;
grant all on public.impjo_staff_link_codes,public.impjo_staff_line_links to service_role;

create function public.impjo_register_pending(p_uid uuid) returns void language plpgsql set search_path='' as $$
declare mail text; actor uuid;
begin
 select email into mail from impjo_private.staff_auth(p_uid) where not banned;
 if mail is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_uid::text,0));
 select principal_id into actor from public.impjo_staff_identities where auth_user_id=p_uid;
 if actor is null then
  insert into public.impjo_principals(kind,name) values('STAFF',mail) returning id into actor;
  insert into public.impjo_staff_identities values(p_uid,actor);
  insert into public.impjo_events(action,target_id) values('STAFF_REGISTRATION_PENDING',actor);
 end if;
end $$;

create function public.impjo_team_link(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql set search_path='' as $$
declare person public.impjo_principals; admin boolean; target public.impjo_staff_line_links; role_ok boolean;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if person.state is distinct from 'APPROVED' or person.kind<>'STAFF' then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
 select exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN') into admin;
 select exists(select 1 from public.impjo_roles where principal_id=p_actor and role='OPERATOR') into role_ok;
 if p_action='create_code' then
  if not role_ok then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  if coalesce(p_data->>'hash','') !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_CODE' using errcode='22023'; end if;
  update public.impjo_staff_link_codes set used_at=now() where staff_id=p_actor and used_at is null;
  insert into public.impjo_staff_link_codes(token_hash,staff_id) values(p_data->>'hash',p_actor);
  insert into public.impjo_events(actor_id,action,target_id) values(p_actor,'LINE_LINK_CODE_CREATED',p_actor);
  return jsonb_build_object('ok',true);
 elsif p_action='mine' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'state',l.state,'created_at',l.created_at,'line_name',p.name)) from public.impjo_staff_line_links l join public.impjo_principals p on p.id=l.line_id where staff_id=p_actor and l.state<>'REVOKED'),'[]');
 end if;
 if not admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
 if p_action='list' then
  return coalesce((select jsonb_agg(to_jsonb(l)||jsonb_build_object('line_name',lp.name,'staff_name',sp.name)) from public.impjo_staff_line_links l join public.impjo_principals lp on lp.id=l.line_id join public.impjo_principals sp on sp.id=l.staff_id where l.state<>'REVOKED'),'[]');
 elsif p_action in ('approve','revoke') then
  select * into target from public.impjo_staff_line_links where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
  if p_action='approve' then
   if target.state<>'PENDING' or not exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=target.staff_id and p.kind='STAFF' and p.state='APPROVED' and r.role='OPERATOR') or not exists(select 1 from public.impjo_principals where id=target.line_id and kind='LINE' and state in ('PENDING','APPROVED')) then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
   update public.impjo_staff_line_links set state='APPROVED',approved_by=p_actor,approved_at=now() where id=target.id;
  else update public.impjo_staff_line_links set state='REVOKED' where id=target.id;
  end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'STAFF_LINE_LINK_'||upper(p_action),target.staff_id,target.line_id::text);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;

create function public.impjo_claim_team_link(p_subject text,p_hash text) returns jsonb language plpgsql set search_path='' as $$
declare code public.impjo_staff_link_codes; line_actor uuid;
begin
 select l.principal_id into line_actor from public.impjo_line_identities l join public.impjo_principals p on p.id=l.principal_id where l.subject=p_subject and p.state in ('PENDING','APPROVED');
 if line_actor is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into code from public.impjo_staff_link_codes where token_hash=p_hash for update;
 if not found or code.used_at is not null or code.expires_at<=now() then raise exception 'INVALID_CODE' using errcode='22023'; end if;
 if not exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=code.staff_id and p.state='APPROVED' and p.kind='STAFF' and r.role='OPERATOR') then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
 insert into public.impjo_staff_line_links(line_id,staff_id) values(line_actor,code.staff_id);
 update public.impjo_staff_link_codes set used_at=now() where token_hash=p_hash;
 insert into public.impjo_events(actor_id,action,target_id,detail) values(line_actor,'STAFF_LINE_LINK_REQUESTED',code.staff_id,line_actor::text);
 return jsonb_build_object('ok',true);
end $$;

create function public.impjo_chat_staff_actor(p_subject text) returns uuid language plpgsql set search_path='' as $$
declare actor uuid; uid uuid; valid boolean;
begin
 select l.staff_id,s.auth_user_id into actor,uid from public.impjo_staff_line_links l
 join public.impjo_line_identities i on i.principal_id=l.line_id
 join public.impjo_principals lp on lp.id=l.line_id
 join public.impjo_principals p on p.id=l.staff_id
 join public.impjo_roles r on r.principal_id=p.id and r.role='OPERATOR'
 join public.impjo_staff_identities s on s.principal_id=p.id
 where i.subject=p_subject and l.state='APPROVED' and lp.state in ('PENDING','APPROVED') and p.state='APPROVED' and p.kind='STAFF';
 if actor is null then return null; end if;
 select confirmed and not banned into valid from impjo_private.staff_auth(uid);
 if not coalesce(valid,false) then return null; end if;
 return actor;
end $$;

create function public.impjo_handover_list(p_actor uuid,p_page int default 1,p_search text default '') returns jsonb language plpgsql set search_path='' as $$
declare staff boolean; outsourced boolean; result jsonb;
begin
 if not exists(select 1 from public.impjo_principals where id=p_actor and state='APPROVED') then raise exception 'APPROVAL_REQUIRED' using errcode='42501'; end if;
 select exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.kind='STAFF' and r.role='OPERATOR') into staff;
 select exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.kind='LINE' and r.role='OUTSOURCE') into outsourced;
 if not staff and not outsourced then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
 with eligible as(select b.*,j.number as job_number,j.job_date from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id
 where b.status='PENDING_HANDOVER' and (staff or exists(select 1 from public.impjo_assignments a where a.bl_id=b.id and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null))
 and (coalesce(p_search,'')='' or strpos(lower(j.number||' '||b.number),lower(left(p_search,200)))>0)),
 paged as(select * from eligible order by job_date nulls last,job_number,number limit 5 offset ((greatest(1,least(p_page,100000))-1)*5))
 select jsonb_build_object('total',(select count(*) from eligible),'bls',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]')) into result;
 return result;
end $$;
revoke all on function public.impjo_register_pending(uuid),public.impjo_team_link(uuid,text,jsonb),public.impjo_claim_team_link(text,text),public.impjo_chat_staff_actor(text),public.impjo_handover_list(uuid,int,text) from public,anon,authenticated;
grant execute on function public.impjo_register_pending(uuid),public.impjo_team_link(uuid,text,jsonb),public.impjo_claim_team_link(text,text),public.impjo_chat_staff_actor(text),public.impjo_handover_list(uuid,int,text) to service_role;

-- Changing approval/roles permanently revokes linked chat authority too.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='update public.impjo_sessions set revoked_at=now() where principal_id=v_target;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected live approval rule'; end if;
 execute replace(definition,needle,needle||E'\n  update public.impjo_staff_line_links set state=''REVOKED'' where (staff_id=v_target or line_id=v_target) and state<>''REVOKED'';');
end;
$migration$;
