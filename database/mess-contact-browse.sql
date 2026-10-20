-- Approved MESS may READ all active jobs. Status writes retain assignment checks.
create or replace function public.impjo_visible_bl(p_actor uuid,p_bl uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.state='APPROVED' and p.archived_at is null and r.role in ('ADMIN','OPERATOR','OUTSOURCE','MESS'))
 and exists(select 1 from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where b.id=p_bl and j.archived_at is null)
$$;
revoke all on function public.impjo_visible_bl(uuid,uuid) from public,anon,authenticated;
grant execute on function public.impjo_visible_bl(uuid,uuid) to service_role;

-- B/L pagination, rather than Job pagination, ensures no B/L is dropped in LINE.
create function public.impjo_mess_browse(p_actor uuid,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare result jsonb; page int:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000)); today date:=(now() at time zone 'Asia/Bangkok')::date;
begin
 if not exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.kind='LINE' and p.state='APPROVED' and p.archived_at is null and r.role='MESS') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if coalesce(p_data->>'mode','contacts')='contacts' then
  with contacts as(select j.contact,min(j.id::text) as key,count(*) as bl_count from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id where public.impjo_visible_bl(p_actor,b.id) and (j.job_date=today or (j.job_date<today and b.status<>'COMPLETED')) group by j.contact),
  paged as(select * from contacts order by lower(contact),contact limit 10 offset ((page-1)*10))
  select jsonb_build_object('total',(select count(*) from contacts),'contacts',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]')) into result;
 else
  with selected as(select contact from public.impjo_jobs where id=(p_data->>'contact_key')::uuid and archived_at is null),
  eligible as(select b.id,b.number,b.status,j.id as job_id,j.number as job_number,j.job_date,j.contact,exists(select 1 from public.impjo_assignments a where a.bl_id=b.id and a.principal_id=p_actor and a.role='MESS' and a.revoked_at is null) as can_report from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where public.impjo_visible_bl(p_actor,b.id) and j.contact=(select contact from selected) and (j.job_date=today or (j.job_date<today and b.status<>'COMPLETED'))),
  paged as(select * from eligible order by job_date,job_number,number,id limit 5 offset ((page-1)*5))
  select jsonb_build_object('total',(select count(*) from eligible),'bls',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]')) into result;
 end if;
 return result;
end $$;
revoke all on function public.impjo_mess_browse(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_mess_browse(uuid,jsonb) to service_role;

-- Keep the web's action buttons aligned with the unchanged status-write rule.
do $migration$
declare definition text; needle text:='to_jsonb(b)||jsonb_build_object(''can_handover'',';
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected live detail shape';end if;
 execute replace(definition,needle,'to_jsonb(b)||jsonb_build_object(''can_report'',exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=b.id and a.principal_id=p_actor and a.role=''MESS'' and a.revoked_at is null),''can_handover'',');
end $migration$;

