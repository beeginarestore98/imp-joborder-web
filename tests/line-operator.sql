begin;
set local role service_role;
do $$
declare a uuid;o uuid;j uuid;b uuid;subject text:='U'||replace(gen_random_uuid()::text,'-','');denied boolean;result jsonb;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA LINE OP ADMIN') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA LINE OP') returning id into o;
 insert into public.impjo_roles values(a,'ADMIN'),(o,'MESS');
 insert into public.impjo_line_identities(provider,subject,principal_id) values('2005629037',subject,o);
 assert public.impjo_operator_actor(subject) is null,'MESS elevated by command';
 perform public.impjo_api(a,'approve',jsonb_build_object('id',o,'role','OPERATOR','state','APPROVED'));
 assert public.impjo_operator_actor(subject)=o,'Approved LINE OPERATOR not resolved';
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA LINE OP','000','ROLLBACK',a,(now() at time zone 'Asia/Bangkok')::date) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination) values(j,'QA-LINE-OP','QA','QA') returning id into b;
 result:=public.impjo_api(o,'detail',jsonb_build_object('id',j));
 assert (result->'jobs'->0->'bls'->0->>'can_handover')::boolean,'LINE OP handover capability absent';
 perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));
 assert exists(select 1 from public.impjo_events where actor_id=o and target_id=b and after_status='IN_PROGRESS'),'LINE actor audit missing';
 perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status','COMPLETED'));
 perform public.impjo_api(o,'status',jsonb_build_object('bl_id',b,'status','IN_PROGRESS'));
 denied:=false;begin perform public.impjo_api(o,'approve',jsonb_build_object('id',a,'role','ADMIN','state','APPROVED'));exception when insufficient_privilege then denied:=true;end;assert denied,'LINE OP escalated another account';
 denied:=false;begin perform public.impjo_api(a,'approve',jsonb_build_object('id',o,'role','ADMIN','state','APPROVED'));exception when invalid_parameter_value then denied:=true;end;assert denied,'LINE silently elevated to staff ADMIN';
 perform public.impjo_api(a,'approve',jsonb_build_object('id',o,'role','OPERATOR','state','DISABLED'));
 assert public.impjo_operator_actor(subject) is null,'Disabled LINE OP retained access';
 assert not has_function_privilege('authenticated','public.impjo_operator_actor(text)','EXECUTE'),'Direct identity impersonation';
end $$;
rollback;
select 'PASS: admin-approved LINE OP handover, actor audit, MESS/admin boundaries, disabled-account denial; fixtures rolled back' as result;

