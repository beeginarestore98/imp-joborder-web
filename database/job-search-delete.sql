create function public.impjo_search_jobs(p_actor uuid,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals;roles text[];current_only boolean;q text;field text;status_filter text;sort_by text;d1 date;d2 date;page_no int;page_size int;result jsonb;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if person.id is null or person.state<>'APPROVED' or person.archived_at is not null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select coalesce(array_agg(role),array[]::text[]) into roles from public.impjo_roles where principal_id=p_actor;
 if not roles&&array['ADMIN','OPERATOR','OUTSOURCE','MESS'] then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 current_only:=not roles&&array['ADMIN','OPERATOR'] and 'MESS'=any(roles);
 q:=left(btrim(coalesce(p_data->>'search','')),200);field:=coalesce(p_data->>'field','all');status_filter:=coalesce(p_data->>'status','');sort_by:=coalesce(p_data->>'sort','date_desc');
 if field not in ('all','job','bl','consignee') or sort_by not in ('date_desc','date_asc','number_desc','number_asc','contact_asc','consignee_asc') or status_filter not in ('','PENDING_HANDOVER','IN_PROGRESS','ISSUE_REPORTED','COMPLETED') then raise exception 'INVALID_SEARCH_FILTER';end if;
 begin
  if nullif(p_data->>'from','') is not null then
   if p_data->>'from' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_DATE_RANGE';end if;d1:=(p_data->>'from')::date;
  end if;
  if nullif(p_data->>'to','') is not null then
   if p_data->>'to' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVALID_DATE_RANGE';end if;d2:=(p_data->>'to')::date;
  end if;
 exception when datetime_field_overflow or invalid_datetime_format then raise exception 'INVALID_DATE_RANGE';end;
 if d1>d2 or d1<date '1900-01-01' or d1>date '9999-12-31' or d2<date '1900-01-01' or d2>date '9999-12-31' then raise exception 'INVALID_DATE_RANGE';end if;
 page_no:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000));page_size:=greatest(1,least(coalesce((p_data->>'size')::int,10),50));
 with matched_bls as materialized(
  select b.* from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id
  where j.archived_at is null and public.impjo_visible_bl(p_actor,b.id)
   and (not current_only or j.job_date=(now() at time zone 'Asia/Bangkok')::date or (j.job_date<(now() at time zone 'Asia/Bangkok')::date and b.status<>'COMPLETED'))
   and (d1 is null or j.job_date>=d1) and (d2 is null or j.job_date<=d2)
   and (status_filter='' or b.status=status_filter)
   and (q='' or strpos(lower(case field when 'job' then j.number when 'bl' then b.number||' '||b.hbl when 'consignee' then b.consignee else j.number||' '||j.contact||' '||b.number||' '||b.hbl||' '||b.consignee||' '||b.destination end),lower(q))>0)
 ),matched_jobs as(
  select j.*,(select min(lower(b.consignee)) from matched_bls b where b.job_id=j.id) as consignee_sort from public.impjo_jobs j where exists(select 1 from matched_bls b where b.job_id=j.id)
 ),ranked as(
  select j.*,row_number() over(order by
   case when sort_by='date_desc' then job_date end desc nulls last,case when sort_by='date_asc' then job_date end asc nulls last,
   case when sort_by='number_desc' then number end desc,case when sort_by='number_asc' then number end asc,
   case when sort_by='contact_asc' then lower(contact) end asc,case when sort_by='consignee_asc' then consignee_sort end asc,
   created_at desc,id) as row_no from matched_jobs j
 ),paged as(select * from ranked order by row_no limit page_size offset ((page_no-1)*page_size))
 select jsonb_build_object('total',(select count(*) from matched_jobs),'total_bls',(select count(*) from matched_bls),'page',page_no,'size',page_size,
  'jobs',coalesce((select jsonb_agg((to_jsonb(j)-'row_no'-'consignee_sort')||jsonb_build_object('bls',(select jsonb_agg(to_jsonb(b) order by lower(b.consignee),b.number,b.id) from matched_bls b where b.job_id=j.id)) order by row_no) from paged j),'[]')) into result;
 return result;
end $$;
revoke all on function public.impjo_search_jobs(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_search_jobs(uuid,jsonb) to service_role;

create function public.impjo_delete_job(p_actor uuid,p_id uuid,p_version timestamptz) returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals;job public.impjo_jobs;bl_ids uuid[];n int;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if person.id is null or person.kind<>'STAFF' or person.state<>'APPROVED' or person.archived_at is not null
  or not exists(select 1 from public.impjo_roles where principal_id=p_actor and role in ('ADMIN','OPERATOR')) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select * into job from public.impjo_jobs where id=p_id for update;
 if job.id is null then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 if p_version is null or p_version<>job.updated_at then raise exception 'STALE_JOB';end if;
 perform 1 from public.impjo_bls where job_id=p_id order by id for update;
 select coalesce(array_agg(id),array[]::uuid[]),count(*) into bl_ids,n from public.impjo_bls where job_id=p_id;
 delete from public.impjo_assignments where bl_id=any(bl_ids);
 -- Purge job/BL history and snapshots, including old chat proposal drafts.
 delete from public.impjo_events where target_id=p_id or target_id=any(bl_ids);
 -- Preserve only the outbox's deduplication slot; no deleted business content remains.
 update public.impjo_report_outbox set payload='{}',state='CANCELLED',lease=null,locked_until=null,error='JOB_DELETED' where strpos(payload::text,job.number)>0;
 delete from public.impjo_bls where job_id=p_id;
 delete from public.impjo_jobs where id=p_id;
 insert into public.impjo_events(actor_id,action,detail) values(p_actor,'JOB_PERMANENTLY_DELETED',jsonb_build_object('jobs',1,'bls',n)::text);
 return jsonb_build_object('ok',true,'deleted',true,'bl_count',n);
end $$;
revoke all on function public.impjo_delete_job(uuid,uuid,timestamptz) from public,anon,authenticated;
grant execute on function public.impjo_delete_job(uuid,uuid,timestamptz) to service_role;

