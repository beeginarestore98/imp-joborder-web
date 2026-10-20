begin;
set local role service_role;
do $$
declare a uuid;o uuid;x uuid;m uuid;j uuid;b uuid;denied boolean;s text;result jsonb;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA FLEX OP') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA FLEX OUT') returning id into o;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA FLEX OTHER') returning id into x;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA FLEX MESS') returning id into m;
 insert into public.impjo_roles values(a,'OPERATOR'),(o,'OUTSOURCE'),(x,'OUTSOURCE'),(m,'MESS');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA FLEX','000','ROLLBACK',a,(now() at time zone 'Asia/Bangkok')::date) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination,status) values(j,'QA-FLEX','QA','QA','COMPLETED') returning id into b;
 insert into public.impjo_assignments(bl_id,principal_id,role,assigned_by) values(b,o,'OUTSOURCE',a),(b,m,'MESS',a);
 foreach s in array array['IN_PROGRESS','ISSUE_REPORTED','PENDING_HANDOVER','COMPLETED'] loop
  perform public.impjo_api(a,'status',jsonb_build_object('bl_id',b,'status',s,'detail','QA issue'));
 end loop;
 foreach s in array array['IN_PROGRESS','ISSUE_REPORTED','PENDING_HANDOVER','COMPLETED'] loop
  perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status',s,'detail','QA issue'));
 end loop;
 assert (select count(*) from public.impjo_events where target_id=b and action='BL_STATUS_CHANGED')=8,'Missing transition history';
 result:=public.impjo_api(o,'detail',jsonb_build_object('id',j));
 assert (result->'jobs'->0->'bls'->0->>'can_update')::boolean,'Assigned OUTSOURCE capability absent';
 result:=public.impjo_api(x,'detail',jsonb_build_object('id',j));
 assert not (result->'jobs'->0->'bls'->0->>'can_update')::boolean,'Other OUTSOURCE capability leaked';
 denied:=false;begin perform public.impjo_api(x,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));exception when insufficient_privilege then denied:=true;end;assert denied,'Unassigned OUTSOURCE reopened work';
 denied:=false;begin perform public.impjo_api(m,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));exception when insufficient_privilege then denied:=true;end;assert denied,'MESS reopened completed work';
 denied:=false;begin perform public.impjo_api(a,'status',jsonb_build_object('bl_id',b,'status','ISSUE_REPORTED'));exception when invalid_parameter_value then denied:=true;end;assert denied,'Issue without details accepted';
 denied:=false;begin perform public.impjo_api(a,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS','expected_status','PENDING_HANDOVER'));exception when invalid_parameter_value then denied:=true;end;assert denied,'Stale confirmation overwrote newer status';
 perform public.impjo_api(a,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS','expected_status','COMPLETED'));
 perform public.impjo_api(m,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));
 assert (select status='COMPLETED' from public.impjo_bls where id=b),'MESS reporting after reopening failed';
 assert (public.impjo_handover_list(a,1,'QA-FLEX')->>'total')::int=1,'Completed work missing from chat update list';
end $$;
rollback;
select 'PASS: OPERATOR and assigned OUTSOURCE all statuses, reopening, immutable audit, MESS boundary, required issue details, stale-write rejection; all fixtures rolled back' as result;

