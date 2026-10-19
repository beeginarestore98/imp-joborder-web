begin;
create sequence public.impjo_job_number_seq;
create table public.impjo_principals (
 id uuid primary key default gen_random_uuid(), kind text not null check(kind in ('STAFF','LINE')),
 name text not null default '', state text not null default 'PENDING' check(state in ('PENDING','APPROVED','REJECTED','DISABLED')),
 created_at timestamptz not null default now()
);
create table public.impjo_staff_identities (auth_user_id uuid primary key references auth.users(id),principal_id uuid not null unique references public.impjo_principals(id));
create table public.impjo_line_identities (provider text not null,subject text not null,principal_id uuid not null unique references public.impjo_principals(id),primary key(provider,subject));
create table public.impjo_roles (principal_id uuid references public.impjo_principals(id),role text check(role in ('ADMIN','OPERATOR','OUTSOURCE','MESS')),primary key(principal_id,role));
create table public.impjo_jobs (
 id uuid primary key default gen_random_uuid(), number text not null unique default ('IMP-'||to_char(now() at time zone 'Asia/Bangkok','YYYY')||'-'||lpad(nextval('public.impjo_job_number_seq')::text,7,'0')),
 contact text not null check(length(btrim(contact)) between 1 and 120),phone text not null check(length(btrim(phone)) between 1 and 30),
 purpose text not null check(length(btrim(purpose)) between 1 and 250),laem boolean not null default false,notes text not null default '' check(length(notes)<=2000),
 created_by uuid not null references public.impjo_principals(id),created_at timestamptz not null default now()
);
create table public.impjo_bls (
 id uuid primary key default gen_random_uuid(),job_id uuid not null references public.impjo_jobs(id),
 number text not null check(length(btrim(number)) between 1 and 200),hbl text not null default '' check(length(hbl)<=200),
 consignee text not null check(length(btrim(consignee)) between 1 and 200),destination text not null check(length(btrim(destination)) between 1 and 200),
 status text not null default 'PENDING_HANDOVER' check(status in ('PENDING_HANDOVER','IN_PROGRESS','ISSUE_REPORTED','COMPLETED'))
);
create unique index impjo_bl_number_per_job on public.impjo_bls(job_id,lower(btrim(number)));
create index impjo_jobs_created on public.impjo_jobs(created_at desc,id);
create index impjo_bls_job on public.impjo_bls(job_id);
create table public.impjo_assignments (
 id uuid primary key default gen_random_uuid(),bl_id uuid not null references public.impjo_bls(id),principal_id uuid not null references public.impjo_principals(id),
 role text not null check(role in ('OUTSOURCE','MESS')),assigned_by uuid not null references public.impjo_principals(id),created_at timestamptz not null default now(),revoked_at timestamptz
);
create unique index impjo_one_active_assignment on public.impjo_assignments(bl_id,role) where revoked_at is null;
create index impjo_assignment_actor on public.impjo_assignments(principal_id,bl_id) where revoked_at is null;
create table public.impjo_events (
 id bigint generated always as identity primary key,actor_id uuid references public.impjo_principals(id),action text not null,
 target_id uuid,before_status text,after_status text,detail text not null default '',created_at timestamptz not null default now()
);
create index impjo_events_created on public.impjo_events(created_at desc);
create table public.impjo_sessions (token_hash text primary key check(length(token_hash)=64),principal_id uuid not null references public.impjo_principals(id),expires_at timestamptz not null,revoked_at timestamptz,created_at timestamptz not null default now());
create index impjo_sessions_actor on public.impjo_sessions(principal_id);
create table public.impjo_webhook_events (event_id text primary key,state text not null default 'PROCESSING' check(state in ('PROCESSING','DONE')),created_at timestamptz not null default now(),completed_at timestamptz);

do $$ declare t text; begin
 foreach t in array array['impjo_principals','impjo_staff_identities','impjo_line_identities','impjo_roles','impjo_jobs','impjo_bls','impjo_assignments','impjo_events','impjo_sessions','impjo_webhook_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public, anon, authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
revoke all on sequence public.impjo_job_number_seq,public.impjo_events_id_seq from public,anon,authenticated;
grant usage,select on sequence public.impjo_job_number_seq,public.impjo_events_id_seq to service_role;

-- Only trusted Backend may call these functions. They are SECURITY INVOKER.
create function public.impjo_staff_actor(p_uid uuid) returns uuid language plpgsql set search_path='' as $$
declare v_actor uuid; v_email text; v_confirmed boolean; v_banned boolean;
begin
 select email,email_confirmed_at is not null,coalesce(banned_until>now(),false) into v_email,v_confirmed,v_banned from auth.users where id=p_uid;
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
create function public.impjo_line_session(p_subject text,p_hash text) returns uuid language plpgsql set search_path='' as $$
declare v_actor uuid;
begin
 if p_subject !~ '^U[0-9a-f]{32}$' or p_hash !~ '^[0-9a-f]{64}$' then raise exception 'INVALID_IDENTITY'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_subject,0));
 select principal_id into v_actor from public.impjo_line_identities where provider='2005629037' and subject=p_subject;
 if v_actor is null then
  insert into public.impjo_principals(kind,name) values('LINE','ผู้ใช้ LINE รออนุมัติ') returning id into v_actor;
  insert into public.impjo_line_identities values('2005629037',p_subject,v_actor);
  insert into public.impjo_events(actor_id,action,target_id) values(v_actor,'LINE_REGISTRATION',v_actor);
 end if;
 if exists(select 1 from public.impjo_principals where id=v_actor and state in ('DISABLED','REJECTED')) then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
 insert into public.impjo_sessions(token_hash,principal_id,expires_at) values(p_hash,v_actor,now()+interval '8 hours');
 return v_actor;
end $$;
create function public.impjo_session_actor(p_hash text) returns uuid language sql stable set search_path='' as $$
 select s.principal_id from public.impjo_sessions s join public.impjo_principals p on p.id=s.principal_id where s.token_hash=p_hash and s.revoked_at is null and s.expires_at>now() and p.state not in ('DISABLED','REJECTED')
$$;
create function public.impjo_line_actor(p_subject text) returns uuid language sql stable set search_path='' as $$
 select principal_id from public.impjo_line_identities where provider='2005629037' and subject=p_subject
$$;
create function public.impjo_visible_bl(p_actor uuid,p_bl uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.impjo_principals p where p.id=p_actor and p.state='APPROVED') and (
 exists(select 1 from public.impjo_roles where principal_id=p_actor and role in ('ADMIN','OPERATOR')) or
 exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.principal_id=p_actor and a.bl_id=p_bl and a.revoked_at is null))
$$;
create function public.impjo_api(p_actor uuid,p_action text,p_data jsonb default '{}'::jsonb) returns jsonb language plpgsql set search_path='' as $$
declare v_person public.impjo_principals; v_roles text[]; v_admin boolean; v_staff boolean; v_job uuid; v_bl uuid; v_target uuid;
 v_json jsonb; v_item jsonb; v_old text; v_new text; v_role text; v_state text; v_page int; v_size int; v_search text; v_filter text;
begin
 select * into v_person from public.impjo_principals where id=p_actor for share;
 if not found then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select coalesce(array_agg(role),array[]::text[]) into v_roles from public.impjo_roles where principal_id=p_actor;
 if p_action='me' then return to_jsonb(v_person)||jsonb_build_object('roles',v_roles); end if;
 if v_person.state<>'APPROVED' then raise exception 'APPROVAL_REQUIRED' using errcode='42501'; end if;
 v_admin:='ADMIN'=any(v_roles); v_staff:=v_admin or 'OPERATOR'=any(v_roles);
 if p_action in ('list','detail') then
  v_page:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000)); v_size:=greatest(1,least(coalesce((p_data->>'size')::int,10),50));
  v_search:=left(coalesce(p_data->>'search',''),200); v_filter:=coalesce(p_data->>'status','');
  if p_action='detail' then v_job:=(p_data->>'id')::uuid; end if;
  with visible as (select b.* from public.impjo_bls b where public.impjo_visible_bl(p_actor,b.id)),
  matched as (select j.* from public.impjo_jobs j where (v_job is null or j.id=v_job) and exists(select 1 from visible b where b.job_id=j.id and (v_filter='' or b.status=v_filter) and (v_search='' or strpos(lower(j.number||' '||j.contact||' '||b.number||' '||b.hbl||' '||b.consignee||' '||b.destination),lower(v_search))>0))),
  paged as (select * from matched order by created_at desc,id limit v_size offset ((v_page-1)*v_size))
  select jsonb_build_object('total',(select count(*) from matched),'page',v_page,'size',v_size,'jobs',coalesce((select jsonb_agg(to_jsonb(j)||jsonb_build_object('bls',(select jsonb_agg(to_jsonb(b) order by b.number) from visible b where b.job_id=j.id)) order by j.created_at desc,j.id) from paged j),'[]'::jsonb)) into v_json;
  if p_action='detail' and (v_json->>'total')::int=0 then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
  return v_json;
 elsif p_action='dashboard' then
  return (select jsonb_build_object('jobs',count(distinct job_id),'bls',count(*),'pending',count(*) filter(where status='PENDING_HANDOVER'),'progress',count(*) filter(where status='IN_PROGRESS'),'issues',count(*) filter(where status='ISSUE_REPORTED'),'completed',count(*) filter(where status='COMPLETED')) from public.impjo_bls b where public.impjo_visible_bl(p_actor,b.id));
 elsif p_action='create' then
  if not v_staff or v_person.kind<>'STAFF' then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  if jsonb_typeof(p_data->'bls') is distinct from 'array' or jsonb_array_length(p_data->'bls') not between 1 and 50 then raise exception 'INVALID_BL_LIST' using errcode='22023'; end if;
  insert into public.impjo_jobs(contact,phone,purpose,laem,notes,created_by) values(btrim(p_data->>'contact'),btrim(p_data->>'phone'),btrim(p_data->>'purpose'),coalesce((p_data->>'laem')::boolean,false),coalesce(p_data->>'notes',''),p_actor) returning id into v_job;
  for v_item in select * from jsonb_array_elements(p_data->'bls') loop
   insert into public.impjo_bls(job_id,number,hbl,consignee,destination) values(v_job,btrim(v_item->>'number'),btrim(coalesce(v_item->>'hbl','')),btrim(v_item->>'consignee'),btrim(v_item->>'destination'));
  end loop;
  insert into public.impjo_events(actor_id,action,target_id) values(p_actor,'JOB_CREATED',v_job);
  return jsonb_build_object('id',v_job);
 elsif p_action='people' then
  if not v_admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  v_page:=greatest(1,coalesce((p_data->>'page')::int,1));
  return jsonb_build_object('people',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('roles',coalesce((select jsonb_agg(role) from public.impjo_roles where principal_id=p.id),'[]'::jsonb))) from (select * from public.impjo_principals order by created_at desc limit 50 offset ((v_page-1)*50)) p),'[]'::jsonb),'total',(select count(*) from public.impjo_principals));
 elsif p_action='approve' then
  if not v_admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  v_target:=(p_data->>'id')::uuid; v_role:=p_data->>'role'; v_state:=p_data->>'state';
  if v_target=p_actor then raise exception 'CANNOT_CHANGE_SELF' using errcode='42501'; end if;
  if v_state not in ('APPROVED','REJECTED','DISABLED') or v_role not in ('ADMIN','OPERATOR','OUTSOURCE','MESS') or v_state is null or v_role is null then raise exception 'INVALID_ROLE' using errcode='22023'; end if;
  perform 1 from public.impjo_principals where id=v_target and ((kind='STAFF' and v_role in ('ADMIN','OPERATOR')) or (kind='LINE' and v_role in ('OUTSOURCE','MESS'))) for update;
  if not found then raise exception 'INVALID_IDENTITY_ROLE' using errcode='22023'; end if;
  update public.impjo_principals set state=v_state,name=coalesce(nullif(left(btrim(p_data->>'name'),120),''),name) where id=v_target;
  delete from public.impjo_roles where principal_id=v_target;
  if v_state='APPROVED' then insert into public.impjo_roles values(v_target,v_role); end if;
  update public.impjo_sessions set revoked_at=now() where principal_id=v_target;
  update public.impjo_assignments set revoked_at=now() where principal_id=v_target and revoked_at is null;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'USER_'||v_state,v_target,v_role);
  return jsonb_build_object('ok',true);
 elsif p_action='assign' then
  if not v_admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  v_bl:=(p_data->>'bl_id')::uuid; v_target:=nullif(p_data->>'principal_id','')::uuid; v_role:=p_data->>'role';
  if v_role is null or v_role not in ('OUTSOURCE','MESS') then raise exception 'INVALID_ROLE' using errcode='22023'; end if;
  perform 1 from public.impjo_bls where id=v_bl for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
  if v_target is not null then
   perform 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=v_target and p.kind='LINE' and p.state='APPROVED' and r.role=v_role for share of p;
   if not found then raise exception 'ASSIGNEE_NOT_APPROVED' using errcode='42501'; end if;
  end if;
  update public.impjo_assignments set revoked_at=now() where bl_id=v_bl and role=v_role and revoked_at is null;
  if v_target is not null then insert into public.impjo_assignments(bl_id,principal_id,role,assigned_by) values(v_bl,v_target,v_role,p_actor); end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'ASSIGNMENT_CHANGED',v_bl,v_role||':'||coalesce(v_target::text,'REVOKED'));
  return jsonb_build_object('ok',true);
 elsif p_action='assignments' then
  if not v_admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('name',p.name)) from public.impjo_assignments a join public.impjo_principals p on p.id=a.principal_id join public.impjo_bls b on b.id=a.bl_id where a.revoked_at is null and b.job_id=(p_data->>'job_id')::uuid),'[]'::jsonb);
 elsif p_action='status' then
  v_bl:=(p_data->>'bl_id')::uuid; v_new:=p_data->>'status';
  select status into v_old from public.impjo_bls where id=v_bl for update;
  if not found or not public.impjo_visible_bl(p_actor,v_bl) then raise exception 'NOT_FOUND' using errcode='P0002'; end if;
  if not ((v_old='PENDING_HANDOVER' and v_new='IN_PROGRESS' and exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null)) or
    (v_old='IN_PROGRESS' and v_new in ('COMPLETED','ISSUE_REPORTED') and exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='MESS' and a.revoked_at is null))) then raise exception 'INVALID_STATUS_TRANSITION' using errcode='42501'; end if;
  if v_new='ISSUE_REPORTED' and length(btrim(coalesce(p_data->>'detail','')))=0 then raise exception 'ISSUE_DETAIL_REQUIRED' using errcode='22023'; end if;
  if length(coalesce(p_data->>'detail',''))>2000 then raise exception 'DETAIL_TOO_LONG' using errcode='22023'; end if;
  update public.impjo_bls set status=v_new where id=v_bl;
  insert into public.impjo_events(actor_id,action,target_id,before_status,after_status,detail) values(p_actor,'BL_STATUS_CHANGED',v_bl,v_old,v_new,coalesce(p_data->>'detail',''));
  return jsonb_build_object('ok',true);
 elsif p_action='audit' then
  if not v_admin then raise exception 'ACCESS_DENIED' using errcode='42501'; end if;
  v_page:=greatest(1,coalesce((p_data->>'page')::int,1));
  return jsonb_build_object('events',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('actor_name',p.name)) from (select * from public.impjo_events order by id desc limit 50 offset ((v_page-1)*50)) e left join public.impjo_principals p on p.id=e.actor_id),'[]'::jsonb),'total',(select count(*) from public.impjo_events));
 else raise exception 'UNKNOWN_ACTION' using errcode='22023';
 end if;
end $$;
do $$ declare f record; begin for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'impjo_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to service_role',f.sig);
end loop;end $$;
commit;

