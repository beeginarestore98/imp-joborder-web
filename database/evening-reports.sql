-- Recipient mappings are empty and automatic delivery is OFF until ADMIN configures it.
create table public.impjo_report_settings(id boolean primary key default true check(id),enabled boolean not null default false,token_hash text not null check(length(token_hash)=64),updated_at timestamptz not null default now());
create table public.impjo_report_recipients(contact_key text primary key,contact_name text not null,recipient_id uuid not null references public.impjo_principals(id),enabled boolean not null default false,updated_by uuid not null references public.impjo_principals(id),updated_at timestamptz not null default now());
create table public.impjo_report_outbox(id uuid primary key default gen_random_uuid(),report_date date not null,contact_key text not null,contact_name text not null,recipient_id uuid not null references public.impjo_principals(id),page int not null,pages int not null,payload jsonb not null,
 state text not null default 'QUEUED' check(state in ('QUEUED','SENDING','SENT','FAILED','CANCELLED')),attempts int not null default 0,lease uuid,locked_until timestamptz,next_attempt_at timestamptz not null default now(),error text not null default '',created_at timestamptz not null default now(),sent_at timestamptz,unique(report_date,contact_key,recipient_id,page));
create index impjo_report_delivery on public.impjo_report_outbox(next_attempt_at) where state in ('QUEUED','FAILED','SENDING');
do $$declare t text;token text;begin
 foreach t in array array['impjo_report_settings','impjo_report_recipients','impjo_report_outbox'] loop
  execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);
 end loop;
 token:=encode(extensions.gen_random_bytes(32),'hex');
 perform vault.create_secret(token,'impjo_evening_report_scheduler','Dedicated IMP report scheduler credential; never expose in frontend');
 insert into public.impjo_report_settings(id,token_hash) values(true,encode(sha256(convert_to(token,'UTF8')),'hex'));
end $$;

create function public.impjo_report_actor(p_line uuid) returns uuid language plpgsql stable set search_path='' as $$
declare mapped uuid;subject text;
begin
 select i.subject into subject from public.impjo_line_identities i join public.impjo_principals p on p.id=i.principal_id where i.principal_id=p_line and p.archived_at is null and p.state in ('PENDING','APPROVED');
 if subject is null then return null;end if;
 mapped:=public.impjo_chat_staff_actor(subject);
 if mapped is not null then return mapped;end if;
 if exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_line and p.kind='LINE' and p.state='APPROVED' and p.archived_at is null and r.role in ('OUTSOURCE','MESS')) then return p_line;end if;
 return null;
end $$;

create function public.impjo_report_groups(p_date date) returns jsonb language sql stable set search_path='' as $$
 with rows as(select lower(btrim(j.contact)) as contact_key,j.contact,j.number as job_number,j.job_date,b.id as bl_id,b.number as bl_number,b.status,
 coalesce((select left(e.detail,120) from public.impjo_events e where e.target_id=b.id and e.action='BL_STATUS_CHANGED' and e.after_status='ISSUE_REPORTED' order by e.id desc limit 1),'') as issue_detail
 from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id left join public.impjo_report_recipients rr on rr.contact_key=lower(btrim(j.contact))
 where j.archived_at is null and j.job_date=p_date and (rr.recipient_id is null or not rr.enabled or public.impjo_report_actor(rr.recipient_id) is null or public.impjo_visible_bl(public.impjo_report_actor(rr.recipient_id),b.id))),
 grouped as(select contact_key,min(contact) as contact_name,jsonb_agg(jsonb_build_object('job_number',job_number,'job_date',job_date,'bl_id',bl_id,'bl_number',bl_number,'status',status,'issue_detail',issue_detail) order by job_number,bl_number,bl_id) as rows,
 jsonb_build_object('total',count(*),'completed',count(*) filter(where status='COMPLETED'),'issues',count(*) filter(where status='ISSUE_REPORTED'),'progress',count(*) filter(where status='IN_PROGRESS'),'pending',count(*) filter(where status='PENDING_HANDOVER')) as summary from rows group by contact_key)
 select coalesce(jsonb_agg(to_jsonb(g)||jsonb_build_object('recipient_name',p.name,'recipient_id',r.recipient_id,'recipient_enabled',coalesce(r.enabled,false),'recipient_ready',public.impjo_report_actor(r.recipient_id) is not null) order by g.contact_key),'[]') from grouped g left join public.impjo_report_recipients r using(contact_key) left join public.impjo_principals p on p.id=r.recipient_id
$$;

create function public.impjo_reports(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare key text;target uuid;d date;
begin
 if not exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.kind='STAFF' and p.state='APPROVED' and p.archived_at is null and r.role='ADMIN') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='settings' then
  return jsonb_build_object('enabled',(select enabled from public.impjo_report_settings where id),'time','17:00','timezone','Asia/Bangkok','contacts',coalesce((select jsonb_agg(to_jsonb(c)) from(select lower(btrim(contact)) as contact_key,min(contact) as contact_name from public.impjo_jobs where archived_at is null and job_date is not null group by lower(btrim(contact)) order by lower(btrim(contact)))c),'[]'),
  'recipients',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('recipient_name',p.name,'ready',public.impjo_report_actor(r.recipient_id) is not null)) from public.impjo_report_recipients r join public.impjo_principals p on p.id=r.recipient_id),'[]'),
  'line_users',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from public.impjo_principals p where p.kind='LINE' and public.impjo_report_actor(p.id) is not null),'[]'),
  'history',coalesce((select jsonb_agg(to_jsonb(h)) from(select id,report_date,contact_name,page,pages,state,attempts,error,sent_at,created_at from public.impjo_report_outbox order by created_at desc,id limit 50)h),'[]'));
 elsif p_action='enabled' then
  update public.impjo_report_settings set enabled=coalesce((p_data->>'enabled')::boolean,false),updated_at=now() where id;
  if not coalesce((p_data->>'enabled')::boolean,false) then update public.impjo_report_outbox set state='CANCELLED',error='SCHEDULE_DISABLED' where state in ('QUEUED','FAILED','SENDING');end if;
  insert into public.impjo_events(actor_id,action,detail) values(p_actor,'EVENING_REPORT_SCHEDULE_CHANGED',jsonb_build_object('enabled',p_data->'enabled','time','17:00','timezone','Asia/Bangkok')::text);
  return jsonb_build_object('ok',true);
 elsif p_action='recipient' then
  key:=lower(btrim(p_data->>'contact_name'));target:=(p_data->>'recipient_id')::uuid;
  if key is null or length(key) not between 1 and 120 or not exists(select 1 from public.impjo_principals where id=target and kind='LINE') or (coalesce((p_data->>'enabled')::boolean,false) and public.impjo_report_actor(target) is null) then raise exception 'INVALID_RECIPIENT' using errcode='22023';end if;
  insert into public.impjo_report_recipients(contact_key,contact_name,recipient_id,enabled,updated_by) values(key,btrim(p_data->>'contact_name'),target,coalesce((p_data->>'enabled')::boolean,false),p_actor)
  on conflict(contact_key) do update set contact_name=excluded.contact_name,recipient_id=excluded.recipient_id,enabled=excluded.enabled,updated_by=p_actor,updated_at=now();
  update public.impjo_report_outbox set state='CANCELLED',error='RECIPIENT_SETTING_CHANGED' where contact_key=key and state in ('QUEUED','FAILED','SENDING');
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'EVENING_REPORT_RECIPIENT_CHANGED',target,jsonb_build_object('contact_name',p_data->>'contact_name','enabled',p_data->'enabled')::text);
  return jsonb_build_object('ok',true);
 elsif p_action='preview' then
  if coalesce(p_data->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_JOB_DATE' using errcode='22023';end if;
  begin d:=(p_data->>'date')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception 'INVALID_JOB_DATE' using errcode='22023';end;
  return jsonb_build_object('date',d,'groups',public.impjo_report_groups(d));
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;

create function impjo_private.enqueue_evening_reports(p_date date default (now() at time zone 'Asia/Bangkok')::date) returns int language plpgsql set search_path='' as $$
declare inserted int;
begin
 if not exists(select 1 from public.impjo_report_settings where id and enabled) then return 0;end if;
 with visible as(select j.number as job_number,j.job_date,b.id as bl_id,b.number as bl_number,b.status,lower(btrim(j.contact)) as contact_key,j.contact,r.recipient_id,
 coalesce((select left(e.detail,120) from public.impjo_events e where e.target_id=b.id and e.action='BL_STATUS_CHANGED' and e.after_status='ISSUE_REPORTED' order by e.id desc limit 1),'') as issue_detail
 from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id join public.impjo_report_recipients r on r.contact_key=lower(btrim(j.contact)) and r.enabled
 where j.archived_at is null and j.job_date=p_date and public.impjo_visible_bl(public.impjo_report_actor(r.recipient_id),b.id)),
 numbered as(select *,((row_number() over(partition by contact_key,recipient_id order by job_number,bl_number,bl_id)-1)/8+1)::int as page from visible),
 totals as(select contact_key,recipient_id,min(contact) as contact_name,max(page) as pages,jsonb_build_object('total',count(*),'completed',count(*) filter(where status='COMPLETED'),'issues',count(*) filter(where status='ISSUE_REPORTED'),'progress',count(*) filter(where status='IN_PROGRESS'),'pending',count(*) filter(where status='PENDING_HANDOVER')) as summary from numbered group by contact_key,recipient_id),
 chunks as(select n.contact_key,n.recipient_id,n.page,jsonb_agg(jsonb_build_object('job_number',job_number,'job_date',job_date,'bl_number',bl_number,'status',status,'issue_detail',issue_detail) order by job_number,bl_number,bl_id) as rows from numbered n group by n.contact_key,n.recipient_id,n.page)
 insert into public.impjo_report_outbox(report_date,contact_key,contact_name,recipient_id,page,pages,payload)
 select p_date,c.contact_key,t.contact_name,c.recipient_id,c.page,t.pages,jsonb_build_object('date',p_date,'contact_name',t.contact_name,'summary',t.summary,'rows',c.rows,'page',c.page,'pages',t.pages) from chunks c join totals t using(contact_key,recipient_id)
 on conflict(report_date,contact_key,recipient_id,page) do nothing;
 get diagnostics inserted=row_count;
 if inserted>0 then insert into public.impjo_events(action,detail) values('EVENING_REPORT_QUEUED',jsonb_build_object('date',p_date,'messages',inserted)::text);end if;
 return inserted;
end $$;

create function public.impjo_report_claim(p_hash text) returns jsonb language plpgsql set search_path='' as $$
declare result jsonb;
begin
 if not exists(select 1 from public.impjo_report_settings where id and token_hash=p_hash) then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
 if not exists(select 1 from public.impjo_report_settings where id and enabled) then return '[]';end if;
 update public.impjo_report_outbox o set state='CANCELLED',error='RECIPIENT_REVOKED_OR_EXPIRED' where o.state in ('QUEUED','FAILED','SENDING') and (o.created_at<now()-interval '23 hours' or public.impjo_report_actor(o.recipient_id) is null or not exists(select 1 from public.impjo_report_recipients r where r.contact_key=o.contact_key and r.recipient_id=o.recipient_id and r.enabled));
 with candidates as(select id from public.impjo_report_outbox where attempts<5 and created_at>now()-interval '23 hours' and next_attempt_at<=now() and (state in ('QUEUED','FAILED') or(state='SENDING' and locked_until<now())) order by created_at,id limit 25 for update skip locked),
 claimed as(update public.impjo_report_outbox o set state='SENDING',attempts=attempts+1,lease=gen_random_uuid(),locked_until=now()+interval '2 minutes' from candidates c where o.id=c.id returning o.*)
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'lease',c.lease,'payload',c.payload)),'[]') into result from claimed c;
 return result;
end $$;

create function public.impjo_report_destination(p_id uuid,p_lease uuid) returns text language sql stable set search_path='' as $$
 select i.subject from public.impjo_report_outbox o join public.impjo_line_identities i on i.principal_id=o.recipient_id join public.impjo_report_recipients r on r.contact_key=o.contact_key and r.recipient_id=o.recipient_id and r.enabled
 where o.id=p_id and o.lease=p_lease and o.state='SENDING' and o.locked_until>now() and public.impjo_report_actor(o.recipient_id) is not null and exists(select 1 from public.impjo_report_settings where id and enabled)
$$;
create function public.impjo_report_finish(p_id uuid,p_lease uuid,p_ok boolean,p_error text default '',p_retry boolean default false) returns void language plpgsql set search_path='' as $$
begin
 update public.impjo_report_outbox set state=case when p_ok then 'SENT' else 'FAILED' end,sent_at=case when p_ok then now() else null end,error=left(p_error,100),attempts=case when not p_ok and not p_retry then 5 else attempts end,next_attempt_at=now()+make_interval(secs=>least(1800,30*(2^attempts)::int)),locked_until=null
 where id=p_id and lease=p_lease and state='SENDING';
 if found then insert into public.impjo_events(action,target_id,detail) values(case when p_ok then 'EVENING_REPORT_ACCEPTED_BY_LINE' else 'EVENING_REPORT_FAILED' end,p_id,left(p_error,100));end if;
end $$;
revoke all on function public.impjo_report_actor(uuid),public.impjo_report_groups(date),public.impjo_reports(uuid,text,jsonb),public.impjo_report_claim(text),public.impjo_report_destination(uuid,uuid),public.impjo_report_finish(uuid,uuid,boolean,text,boolean) from public,anon,authenticated;
grant execute on function public.impjo_report_actor(uuid),public.impjo_report_groups(date),public.impjo_reports(uuid,text,jsonb),public.impjo_report_claim(text),public.impjo_report_destination(uuid,uuid),public.impjo_report_finish(uuid,uuid,boolean,text,boolean) to service_role;
revoke all on function impjo_private.enqueue_evening_reports(date) from public,anon,authenticated,service_role;

create function impjo_private.cancel_archived_job_reports() returns trigger language plpgsql set search_path='' as $$
begin
 if new.archived_at is not null and old.archived_at is null then
  update public.impjo_report_outbox o set state='CANCELLED',error='JOB_ARCHIVED' where o.state in ('QUEUED','FAILED','SENDING') and exists(select 1 from jsonb_array_elements(o.payload->'rows') r where r->>'job_number'=new.number);
 end if;
 return new;
end $$;
revoke all on function impjo_private.cancel_archived_job_reports() from public,anon,authenticated;
create trigger impjo_cancel_archived_job_reports after update of archived_at on public.impjo_jobs for each row execute function impjo_private.cancel_archived_job_reports();
