-- Recoverable deletion, optimistic job editing and server-authorized exports.
alter table public.impjo_jobs add column archived_at timestamptz,add column archived_by uuid references public.impjo_principals(id),add column updated_at timestamptz not null default now();
alter table public.impjo_principals add column archived_at timestamptz,add column archived_by uuid references public.impjo_principals(id);
create index impjo_jobs_active_date on public.impjo_jobs(job_date,id) where archived_at is null;
create function impjo_private.touch_job() returns trigger language plpgsql set search_path='' as $$ begin new.updated_at:=clock_timestamp();return new;end $$;
revoke all on function impjo_private.touch_job() from public,anon,authenticated;
create trigger impjo_touch_job before update on public.impjo_jobs for each row execute function impjo_private.touch_job();

create or replace function public.impjo_visible_bl(p_actor uuid,p_bl uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.impjo_principals p where p.id=p_actor and p.state='APPROVED' and p.archived_at is null)
 and exists(select 1 from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where b.id=p_bl and j.archived_at is null)
 and (exists(select 1 from public.impjo_roles where principal_id=p_actor and role in ('ADMIN','OPERATOR','OUTSOURCE')) or exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.principal_id=p_actor and a.bl_id=p_bl and a.revoked_at is null))
$$;

-- Narrow private Auth bridge: archiving a staff account revokes actual Auth sessions.
create function impjo_private.revoke_staff_sessions(p_actor uuid,p_target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_actor=p_target or not exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.kind='STAFF' and p.state='APPROVED' and p.archived_at is null and r.role='ADMIN') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 delete from auth.sessions where user_id in(select auth_user_id from public.impjo_staff_identities where principal_id=p_target);
end $$;
revoke all on function impjo_private.revoke_staff_sessions(uuid,uuid) from public,anon,authenticated;
grant execute on function impjo_private.revoke_staff_sessions(uuid,uuid) to service_role;

create function public.impjo_manage(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals; admin boolean; staff boolean; job public.impjo_jobs; target public.impjo_principals; item jsonb; old_bls jsonb; result jsonb; d1 date; d2 date; page int; row_count int;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if not found or person.state<>'APPROVED' or person.archived_at is not null or person.kind<>'STAFF' then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN') into admin;
 select admin or exists(select 1 from public.impjo_roles where principal_id=p_actor and role='OPERATOR') into staff;
 if not staff then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 page:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000));
 if p_action in ('archive_account','restore_account','archived_people') then
  if not admin then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  if p_action='archived_people' then
   return jsonb_build_object('people',coalesce((select jsonb_agg(to_jsonb(p)) from(select id,name,kind,state,archived_at from public.impjo_principals where archived_at is not null order by archived_at desc,id limit 50 offset ((page-1)*50))p),'[]'),'total',(select count(*) from public.impjo_principals where archived_at is not null));
  end if;
  if (p_data->>'id')::uuid=p_actor then raise exception 'CANNOT_CHANGE_SELF' using errcode='42501';end if;
  select * into target from public.impjo_principals where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  if p_action='archive_account' then
   if target.archived_at is not null then return jsonb_build_object('ok',true);end if;
   perform impjo_private.revoke_staff_sessions(p_actor,target.id);
   update public.impjo_principals set state='DISABLED',archived_at=now(),archived_by=p_actor where id=target.id;
   update public.impjo_sessions set revoked_at=now() where principal_id=target.id and revoked_at is null;
   update public.impjo_staff_line_links set state='REVOKED' where (staff_id=target.id or line_id=target.id) and state<>'REVOKED';
   update public.impjo_staff_link_codes set used_at=now() where staff_id=target.id and used_at is null;
   update public.impjo_assignments set revoked_at=now() where principal_id=target.id and revoked_at is null;
  else
   if target.archived_at is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
   update public.impjo_principals set state='PENDING',archived_at=null,archived_by=null where id=target.id;
   delete from public.impjo_roles where principal_id=target.id;
  end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,upper(p_action),target.id,'Recoverable account archive; restored accounts require fresh approval and assignments');
  return jsonb_build_object('ok',true);
 elsif p_action='archived_jobs' then
  return jsonb_build_object('jobs',coalesce((select jsonb_agg(to_jsonb(j)) from(select id,number,contact,job_date,archived_at,updated_at from public.impjo_jobs where archived_at is not null order by archived_at desc,id limit 50 offset ((page-1)*50))j),'[]'),'total',(select count(*) from public.impjo_jobs where archived_at is not null));
 elsif p_action='export_jobs' then
  if coalesce(p_data->>'from','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(p_data->>'to','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_DATE_RANGE' using errcode='22023';end if;
  begin d1:=(p_data->>'from')::date;d2:=(p_data->>'to')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception 'INVALID_DATE_RANGE' using errcode='22023';end;
  if d1>d2 or d1<date '1900-01-01' or d2>date '9999-12-31' then raise exception 'INVALID_DATE_RANGE' using errcode='22023';end if;
  with rows as(select j.number as job_number,j.job_date,j.contact,j.phone,j.purpose,j.laem,j.notes,b.number as bl_number,b.hbl,b.consignee,b.destination,b.status,
   coalesce((select e.detail from public.impjo_events e where e.target_id=b.id and e.action='BL_STATUS_CHANGED' and e.after_status='ISSUE_REPORTED' order by e.id desc limit 1),'') as issue_detail,
   coalesce((select p.name from public.impjo_assignments a join public.impjo_principals p on p.id=a.principal_id where a.bl_id=b.id and a.role='OUTSOURCE' and a.revoked_at is null),'') as outsource_name,
   coalesce((select p.name from public.impjo_assignments a join public.impjo_principals p on p.id=a.principal_id where a.bl_id=b.id and a.role='MESS' and a.revoked_at is null),'') as mess_name,j.created_at
   from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id where j.archived_at is null and j.job_date between d1 and d2 order by j.job_date,j.number,b.number,b.id limit 10001)
  select jsonb_build_object('rows',coalesce(jsonb_agg(to_jsonb(rows)),'[]'),'count',count(*)) into result from rows;
  if (result->>'count')::int>10000 then raise exception 'EXPORT_TOO_LARGE' using errcode='22023';end if;
  insert into public.impjo_events(actor_id,action,detail) values(p_actor,'JOBS_EXPORTED',jsonb_build_object('from',d1,'to',d2,'bl_count',result->'count')::text);
  return result;
 elsif p_action in ('edit_job','archive_job','restore_job') then
  select * into job from public.impjo_jobs where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  if p_action='restore_job' then
   if job.archived_at is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
   update public.impjo_jobs set archived_at=null,archived_by=null where id=job.id;
  else
   if job.archived_at is not null then raise exception 'JOB_ARCHIVED' using errcode='42501';end if;
   if nullif(p_data->>'version','') is null or (p_data->>'version')::timestamptz<>job.updated_at then raise exception 'STALE_JOB' using errcode='22023';end if;
   perform 1 from public.impjo_bls where job_id=job.id order by id for update;
   if p_action='archive_job' then
    update public.impjo_jobs set archived_at=now(),archived_by=p_actor where id=job.id;
   else
    if coalesce(p_data->>'job_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_JOB_DATE' using errcode='22023';end if;
    begin d1:=(p_data->>'job_date')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception 'INVALID_JOB_DATE' using errcode='22023';end;
    if d1<date '1900-01-01' or d1>date '9999-12-31' then raise exception 'INVALID_JOB_DATE' using errcode='22023';end if;
    if jsonb_typeof(p_data->'bls') is distinct from 'array' or jsonb_array_length(p_data->'bls') not between 1 and 50 then raise exception 'INVALID_BL_LIST' using errcode='22023';end if;
    if exists(select 1 from public.impjo_bls b where b.job_id=job.id and not exists(select 1 from jsonb_array_elements(p_data->'bls') i where nullif(i->>'id','')::uuid=b.id)) then raise exception 'BL_REMOVAL_NOT_ALLOWED' using errcode='22023';end if;
    if exists(select 1 from jsonb_array_elements(p_data->'bls') i where nullif(i->>'id','') is not null group by i->>'id' having count(*)>1) then raise exception 'INVALID_BL_LIST' using errcode='22023';end if;
    select jsonb_agg(to_jsonb(b) order by b.id) into old_bls from public.impjo_bls b where b.job_id=job.id;
    update public.impjo_jobs set job_date=d1,contact=btrim(p_data->>'contact'),phone=btrim(p_data->>'phone'),purpose=btrim(p_data->>'purpose'),laem=coalesce((p_data->>'laem')::boolean,false),notes=coalesce(p_data->>'notes','') where id=job.id;
    for item in select * from jsonb_array_elements(p_data->'bls') loop
     if nullif(item->>'id','') is null then
      insert into public.impjo_bls(job_id,number,hbl,consignee,destination) values(job.id,btrim(item->>'number'),btrim(coalesce(item->>'hbl','')),btrim(item->>'consignee'),btrim(item->>'destination'));
     else
      update public.impjo_bls set number=btrim(item->>'number'),hbl=btrim(coalesce(item->>'hbl','')),consignee=btrim(item->>'consignee'),destination=btrim(item->>'destination') where id=(item->>'id')::uuid and job_id=job.id;
      if not found then raise exception 'INVALID_BL_LIST' using errcode='22023';end if;
     end if;
    end loop;
   end if;
  end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,upper(p_action),job.id,jsonb_build_object('before',to_jsonb(job),'bls_before',old_bls,'after',(select to_jsonb(j) from public.impjo_jobs j where j.id=job.id),'bls_after',(select jsonb_agg(to_jsonb(b)) from public.impjo_bls b where b.job_id=job.id))::text);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;
revoke all on function public.impjo_manage(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_manage(uuid,text,jsonb) to service_role;

do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 definition:=replace(definition,'if v_person.state<>''APPROVED'' then','if v_person.state<>''APPROVED'' or v_person.archived_at is not null then');
 definition:=replace(definition,'select * from public.impjo_principals order by created_at desc','select * from public.impjo_principals where archived_at is null order by created_at desc');
 definition:=replace(definition,'(select count(*) from public.impjo_principals)','(select count(*) from public.impjo_principals where archived_at is null)');
 definition:=replace(definition,'where id=v_target and ((kind=','where id=v_target and archived_at is null and ((kind=');
 definition:=replace(definition,'select job_date into v_old_date from public.impjo_jobs where id=v_job for update;','select job_date into v_old_date from public.impjo_jobs where id=v_job and archived_at is null for update;');
 needle:='v_bl:=(p_data->>''bl_id'')::uuid; v_new:=p_data->>''status'';';
 if strpos(definition,needle)=0 then raise exception 'Unexpected live status rule';end if;
 definition:=replace(definition,needle,needle||E'\n  perform 1 from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id where b.id=v_bl and j.archived_at is null for share of j;\n  if not found then raise exception ''NOT_FOUND'' using errcode=''P0002'';end if;');
 needle:='perform 1 from public.impjo_bls where id=v_bl for update;';
 definition:=replace(definition,needle,E'perform 1 from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id where b.id=v_bl and j.archived_at is null for share of j;\n  if not found then raise exception ''NOT_FOUND'' using errcode=''P0002'';end if;\n  '||needle);
 execute definition;
 definition:=pg_get_functiondef('public.impjo_handover_list(uuid,integer,text)'::regprocedure);
 if strpos(definition,'where b.status=''PENDING_HANDOVER''')=0 then raise exception 'Unexpected handover list';end if;
 execute replace(definition,'where b.status=''PENDING_HANDOVER''','where j.archived_at is null and b.status=''PENDING_HANDOVER''');
end;
$migration$;
