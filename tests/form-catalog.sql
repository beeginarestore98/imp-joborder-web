begin;
set local role service_role;
do $$
declare a uuid;m uuid;c jsonb;p jsonb;r jsonb;j uuid;b uuid;version timestamptz;denied boolean;payload jsonb;name text:='QA CONTACT '||gen_random_uuid();
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA CATALOG OP') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA CATALOG MESS') returning id into m;
 insert into public.impjo_roles values(a,'OPERATOR'),(m,'MESS');
 c:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','CONTACT','name',name,'phone','0812345678'));
 assert c->>'phone'='0812345678','Contact phone not persisted';
 perform public.impjo_catalog_api(a,'save',jsonb_build_object('kind','CONTACT','name',name,'phone','0899999999'));
 r:=public.impjo_catalog_api(a,'list',jsonb_build_object('kind','CONTACT','q',name));
 assert (r->>'total')::int=1 and r->'rows'->0->>'phone'='0899999999','Contact update duplicated or failed';
 p:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','PURPOSE','name','QA PURPOSE '||gen_random_uuid(),'requires_amount',true));
 payload:=jsonb_build_object('job_date',(now() at time zone 'Asia/Bangkok')::date,'contact',name,'phone','0899999999','purpose','ตามใบเสร็จ','bls',jsonb_build_array(jsonb_build_object('number','QA-CATALOG','consignee','QA','destination','CMA CGM (THAILAND) LTD.')));
 denied:=false;begin perform public.impjo_api(a,'create',payload);exception when invalid_parameter_value then denied:=true;end;assert denied,'Required amount omitted';
 denied:=false;begin perform public.impjo_api(a,'create',payload||'{"amount":"10.999"}');exception when invalid_parameter_value then denied:=true;end;assert denied,'Amount silently rounded';
 denied:=false;begin perform public.impjo_api(a,'create',payload||'{"amount":"-1"}');exception when invalid_parameter_value then denied:=true;end;assert denied,'Negative amount accepted';
 r:=public.impjo_api(a,'create',payload||'{"amount":"1234.50"}');j:=(r->>'id')::uuid;
 assert (select amount=1234.50 from public.impjo_jobs where id=j),'Decimal amount not exact';
 perform public.impjo_catalog_api(a,'archive',jsonb_build_object('id',c->>'id'));
 assert (public.impjo_catalog_api(a,'list',jsonb_build_object('kind','CONTACT','q',name))->>'total')::int=0,'Deleted contact selectable';
 assert (select contact=name and phone='0899999999' from public.impjo_jobs where id=j),'Deleting contact changed historical job';
 select id into b from public.impjo_bls where job_id=j;select updated_at into version from public.impjo_jobs where id=j;
 payload:=payload||jsonb_build_object('id',j,'version',version,'amount','99.99','bls',jsonb_build_array(jsonb_build_object('id',b,'number','QA-CATALOG','consignee','QA','destination','MANUAL DESTINATION')));
 perform public.impjo_manage(a,'edit_job',payload);
 assert (select amount=99.99 from public.impjo_jobs where id=j),'Edited amount lost';
 r:=public.impjo_manage(a,'export_jobs',jsonb_build_object('from',(now() at time zone 'Asia/Bangkok')::date,'to',(now() at time zone 'Asia/Bangkok')::date));
 assert exists(select 1 from jsonb_array_elements(r->'rows')x where x->>'contact'=name and (x->>'amount')::numeric=99.99),'Export omitted amount';
 denied:=false;begin perform public.impjo_catalog_api(m,'list','{"kind":"CONTACT"}');exception when insufficient_privilege then denied:=true;end;assert denied,'MESS accessed staff contact directory';
 assert not has_table_privilege('anon','public.impjo_catalog','SELECT'),'Anonymous catalog access';
 assert not has_function_privilege('authenticated','public.impjo_catalog_api(uuid,text,jsonb)','EXECUTE'),'Direct actor impersonation';
end $$;
rollback;
select 'PASS: contact linkage/edit/archive snapshots, extensible purpose, exact amounts/create/edit/export, validation and staff-only authorization; fixtures rolled back' as result;

