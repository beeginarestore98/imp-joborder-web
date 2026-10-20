begin;
set local role service_role;
do $$
declare o uuid;a uuid;p uuid;j uuid;b uuid;r jsonb;denied boolean;status text;
begin
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA SHARED OUTSOURCE') returning id into o;
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA SHARED OP') returning id into a;
 insert into public.impjo_principals(kind,name) values('LINE','QA PENDING OUT') returning id into p;
 insert into public.impjo_roles values(o,'OUTSOURCE'),(a,'OPERATOR'),(p,'OUTSOURCE');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA SHARED OUT','000','QA',a,(now() at time zone 'Asia/Bangkok')::date) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination) values(j,'QA-SHARED-OUT','QA','QA') returning id into b;
 assert not exists(select 1 from public.impjo_assignments where bl_id=b),'Fixture assigned unexpectedly';
 r:=public.impjo_api(o,'detail',jsonb_build_object('id',j));
 assert (r->'jobs'->0->'bls'->0->>'can_update')::boolean,'Unassigned OUTSOURCE missing update capability';
 assert (public.impjo_handover_list(o,1,'QA-SHARED-OUT')->>'total')::int=1,'Chat omitted shared work';
 foreach status in array array['IN_PROGRESS','COMPLETED','IN_PROGRESS','ISSUE_REPORTED','PENDING_HANDOVER'] loop
  perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status',status,'detail','QA issue'));
 end loop;
 assert (select count(*) from public.impjo_events where actor_id=o and target_id=b and action='BL_STATUS_CHANGED')=5,'Actual OUTSOURCE audit actor missing';
 denied:=false;begin perform public.impjo_api(p,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));exception when insufficient_privilege then denied:=true;end;assert denied,'Pending OUTSOURCE wrote work';
 update public.impjo_principals set state='DISABLED' where id=o;
 denied:=false;begin perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));exception when insufficient_privilege then denied:=true;end;assert denied,'Disabled OUTSOURCE retained write access';
 assert not has_function_privilege('anon','public.impjo_api(uuid,text,jsonb)','EXECUTE'),'Anonymous actor impersonation';
end $$;
rollback;
select 'PASS: approved OUTSOURCE shared updates without assignments, all statuses/reopen, actor audit and approval enforcement; fixtures rolled back' as result;

