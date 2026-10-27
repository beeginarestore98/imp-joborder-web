create table public.impjo_status_notifications(
 id uuid primary key default gen_random_uuid(),event_id bigint not null unique references public.impjo_events(id) on delete cascade,
 bl_id uuid not null references public.impjo_bls(id) on delete cascade,actor_id uuid not null,payload jsonb not null,
 contact_key text not null,recipient_email text,recipient_version timestamptz,
 state text not null check(state in('PENDING','NO_RECIPIENT','SENDING','ACCEPTED','FAILED','UNKNOWN')),
 lease uuid,provider_id text,error text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table public.impjo_status_notifications enable row level security;
revoke all on public.impjo_status_notifications from public,anon,authenticated;
grant all on public.impjo_status_notifications to service_role;
create index impjo_status_notification_bl on public.impjo_status_notifications(bl_id,created_at);
create function public.impjo_queue_status_email() returns trigger language plpgsql set search_path='' as $$
declare person public.impjo_principals;j public.impjo_jobs;b public.impjo_bls;r public.impjo_document_recipients;
begin
 if new.action<>'BL_STATUS_CHANGED' or new.after_status not in('COMPLETED','ISSUE_REPORTED') then return new;end if;
 select * into person from public.impjo_principals where id=new.actor_id and kind='LINE' and state='APPROVED' and archived_at is null;
 if not found or not exists(select 1 from public.impjo_roles where principal_id=new.actor_id and role='MESS') then return new;end if;
 select * into b from public.impjo_bls where id=new.target_id;select * into j from public.impjo_jobs where id=b.job_id;
 if j.id is null or j.archived_at is not null then return new;end if;
 select * into r from public.impjo_document_recipients where contact_key=lower(btrim(j.contact)) and enabled;
 insert into public.impjo_status_notifications(event_id,bl_id,actor_id,contact_key,recipient_email,recipient_version,state,payload)
 values(new.id,b.id,person.id,lower(btrim(j.contact)),r.email,r.updated_at,case when r.email is null then 'NO_RECIPIENT' else 'PENDING' end,
 jsonb_build_object('jobNumber',j.number,'jobDate',j.job_date,'blNumber',b.number,'hbl',b.hbl,'consignee',b.consignee,'destination',b.destination,'contact',j.contact,'status',new.after_status,'issueDetail',case when new.after_status='ISSUE_REPORTED' then new.detail else '' end,'reporter',person.name));
 return new;
end $$;
revoke all on function public.impjo_queue_status_email() from public,anon,authenticated;
grant execute on function public.impjo_queue_status_email() to service_role;
create trigger impjo_queue_status_email after insert on public.impjo_events for each row when(new.action='BL_STATUS_CHANGED') execute function public.impjo_queue_status_email();
create function public.impjo_status_mail(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals;n public.impjo_status_notifications;r public.impjo_document_recipients;admin boolean;newlease uuid;
begin
 select * into person from public.impjo_principals where id=p_actor and state='APPROVED' and archived_at is null for share;
 if not found then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 admin:=person.kind='STAFF' and exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN');
 if not admin and not(person.kind='LINE' and exists(select 1 from public.impjo_roles where principal_id=p_actor and role='MESS')) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select * into n from public.impjo_status_notifications where id=(p_data->>'id')::uuid for update;
 if not found or (n.actor_id<>p_actor and not admin) then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 if not exists(select 1 from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where b.id=n.bl_id and j.archived_at is null) then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 if p_action='claim' then
  if n.state<>'PENDING' then return jsonb_build_object('skip',true,'state',n.state);end if;
  select * into r from public.impjo_document_recipients where contact_key=n.contact_key and enabled;
  if r.email is distinct from n.recipient_email or r.updated_at is distinct from n.recipient_version then
   update public.impjo_status_notifications set state='FAILED',error='RECIPIENT_CHANGED',updated_at=now() where id=n.id;
   return jsonb_build_object('skip',true,'state','RECIPIENT_CHANGED');
  end if;
  newlease:=gen_random_uuid();update public.impjo_status_notifications set state='SENDING',lease=newlease,updated_at=now() where id=n.id;
  return n.payload||jsonb_build_object('to',n.recipient_email,'documentId',n.id,'lease',newlease);
 elsif p_action='finish' then
  if p_data->>'state' not in('ACCEPTED','FAILED','UNKNOWN') or n.state<>'SENDING' or n.lease is distinct from (p_data->>'lease')::uuid then raise exception 'DOCUMENT_CONFLICT' using errcode='22023';end if;
  update public.impjo_status_notifications set state=p_data->>'state',provider_id=left(p_data->>'provider_id',200),error=left(coalesce(p_data->>'error',''),100),updated_at=now() where id=n.id;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'STATUS_EMAIL_RESULT',n.bl_id,jsonb_build_object('notification_id',n.id,'state',p_data->>'state')::text);
  return jsonb_build_object('state',p_data->>'state');
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;
revoke all on function public.impjo_status_mail(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_status_mail(uuid,text,jsonb) to service_role;
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 definition:=replace(definition,'declare','declare v_email_event bigint;');
 needle:=$needle$insert into public.impjo_events(actor_id,action,target_id,before_status,after_status,detail) values(p_actor,'BL_STATUS_CHANGED',v_bl,v_old,v_new,coalesce(p_data->>'detail',''));
  return jsonb_build_object('ok',true);$needle$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected status event insertion';end if;
 execute replace(definition,needle,$replacement$insert into public.impjo_events(actor_id,action,target_id,before_status,after_status,detail) values(p_actor,'BL_STATUS_CHANGED',v_bl,v_old,v_new,coalesce(p_data->>'detail','')) returning id into v_email_event;
  return jsonb_build_object('ok',true,'notification_id',(select id from public.impjo_status_notifications where event_id=v_email_event));$replacement$);
 definition:=pg_get_functiondef('public.impjo_documents(uuid,text,jsonb)'::regprocedure);
 needle:=$needle$'bl_number',b.number,'contact',j.contact);$needle$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected document claim';end if;
 execute replace(definition,needle,$replacement$'bl_number',b.number,'contact',j.contact,'status',b.status,'issue_detail',case when b.status='ISSUE_REPORTED' then (select e.detail from public.impjo_events e where e.target_id=b.id and e.action='BL_STATUS_CHANGED' and e.after_status='ISSUE_REPORTED' order by e.id desc limit 1) else '' end,'reporter',person.name,'destination',b.destination,'hbl',b.hbl,'consignee',b.consignee,'job_date',j.job_date);$replacement$);
end $migration$;
