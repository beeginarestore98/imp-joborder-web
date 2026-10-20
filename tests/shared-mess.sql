begin;
set local role service_role;
do $$
declare a uuid;m uuid;n uuid;p uuid;j uuid;b uuid;denied boolean;result jsonb;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA SHARED OP') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA SHARED MESS A') returning id into m;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA SHARED MESS B') returning id into n;
 insert into public.impjo_principals(kind,name) values('LINE','QA SHARED PENDING') returning id into p;
 insert into public.impjo_roles values(a,'OPERATOR'),(m,'MESS'),(n,'MESS'),(p,'MESS');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA SHARED','000','ROLLBACK',a,(now() at time zone 'Asia/Bangkok')::date) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination,status) values(j,'QA-SHARED','QA','QA','IN_PROGRESS') returning id into b;
 assert not exists(select 1 from public.impjo_assignments where bl_id=b),'Fixture unexpectedly assigned';
 result:=public.impjo_api(m,'detail',jsonb_build_object('id',j));
 assert (result->'jobs'->0->'bls'->0->>'can_report')::boolean,'Unassigned MESS missing web capability';
 result:=public.impjo_mess_browse(n,jsonb_build_object('mode','bls','contact_key',j));
 assert (result->'bls'->0->>'can_report')::boolean,'Unassigned MESS missing chat capability';
 perform public.impjo_api(m,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));
 assert exists(select 1 from public.impjo_events where target_id=b and actor_id=m and after_status='COMPLETED'),'Actual MESS actor missing';
 denied:=false;begin perform public.impjo_api(n,'status',jsonb_build_object('bl_id',b,'status','ISSUE_REPORTED','detail','late update'));exception when insufficient_privilege then denied:=true;end;assert denied,'Second MESS overwrote completed work';
 perform public.impjo_api(a,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));
 denied:=false;begin perform public.impjo_api(n,'status',jsonb_build_object('bl_id',b,'status','ISSUE_REPORTED','detail',' '));exception when invalid_parameter_value then denied:=true;end;assert denied,'Empty issue accepted';
 perform public.impjo_api(n,'status',jsonb_build_object('bl_id',b,'status','ISSUE_REPORTED','detail','QA issue'));
 assert exists(select 1 from public.impjo_events where target_id=b and actor_id=n and after_status='ISSUE_REPORTED'),'Second MESS audit actor missing';
 denied:=false;begin perform public.impjo_api(p,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));exception when insufficient_privilege then denied:=true;end;assert denied,'Pending MESS wrote work';
 update public.impjo_principals set state='DISABLED' where id=m;
 denied:=false;begin perform public.impjo_api(m,'detail',jsonb_build_object('id',j));exception when insufficient_privilege then denied:=true;end;assert denied,'Disabled MESS retained access';
end $$;
rollback;
select 'PASS: shared MESS reporting without assignments, exact actor audit, no completed overwrite, required issue details and approval enforcement; fixtures rolled back' as result;

