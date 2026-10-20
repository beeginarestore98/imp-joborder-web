begin;
set local role service_role;
do $$
declare a uuid;m uuid;x uuid;j uuid;b uuid;result jsonb;denied boolean;today date:=(now() at time zone 'Asia/Bangkok')::date;contact text:='QA CONTACT '||gen_random_uuid();
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA CONTACT ADMIN') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA CONTACT MESS') returning id into m;
 insert into public.impjo_principals(kind,name) values('LINE','QA CONTACT PENDING') returning id into x;
 insert into public.impjo_roles values(a,'ADMIN'),(m,'MESS');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values(contact,'000','ROLLBACK TEST',a,today) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination,status) select j,'CONTACT-'||n,'QA','QA','IN_PROGRESS' from generate_series(1,12)n;
 select id into b from public.impjo_bls where job_id=j limit 1;
 assert public.impjo_visible_bl(m,b),'Unassigned approved MESS cannot view shared job';
 result:=public.impjo_mess_browse(m,jsonb_build_object('mode','bls','contact_key',j,'page',1));
 assert (result->>'total')::int=12 and jsonb_array_length(result->'bls')=5,'BL pagination count incorrect';
 assert not (result->'bls'->0->>'can_report')::boolean,'Read access incorrectly granted status-write capability';
 result:=public.impjo_mess_browse(m,jsonb_build_object('mode','bls','contact_key',j,'page',3));
 assert jsonb_array_length(result->'bls')=2,'Last BL page lost records';
 denied:=false;begin perform public.impjo_api(m,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));exception when insufficient_privilege then denied:=true;end;assert denied,'Unassigned MESS changed shared work';
 perform public.impjo_api(a,'assign',jsonb_build_object('bl_id',b,'role','MESS','principal_id',m));
 perform public.impjo_api(m,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));
 assert exists(select 1 from public.impjo_events where actor_id=m and target_id=b and after_status='COMPLETED'),'Mapped actor audit missing';
 denied:=false;begin perform public.impjo_mess_browse(x,'{}');exception when insufficient_privilege then denied:=true;end;assert denied,'Pending user accessed contacts';
 update public.impjo_jobs set job_date=today+1 where id=j;
 assert (public.impjo_mess_browse(m,jsonb_build_object('mode','bls','contact_key',j))->>'total')::int=0,'Future jobs visible';
 update public.impjo_jobs set job_date=today-1 where id=j;
 assert (public.impjo_mess_browse(m,jsonb_build_object('mode','bls','contact_key',j))->>'total')::int=11,'Completed overdue work visible';
 update public.impjo_jobs set archived_at=now() where id=j;
 assert not public.impjo_visible_bl(m,b),'Archived job visible';
 assert not has_function_privilege('anon','public.impjo_mess_browse(uuid,jsonb)','EXECUTE'),'Anonymous RPC access';
 assert not has_function_privilege('authenticated','public.impjo_mess_browse(uuid,jsonb)','EXECUTE'),'Direct actor impersonation possible';
end $$;
rollback;
select 'PASS: shared MESS reads, contact/BL pagination, assignment-bound writes, date/archive filtering and private RPC; all fixtures rolled back' as result;

