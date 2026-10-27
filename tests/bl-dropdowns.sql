set local role service_role;do $$declare a uuid;m uuid;d jsonb;c jsonb;r jsonb;n text:='QA DROPDOWN '||gen_random_uuid();denied boolean;j uuid;begin
insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA DROPDOWN OP') returning id into a;insert into public.impjo_roles values(a,'OPERATOR');
insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA DROPDOWN MESS') returning id into m;insert into public.impjo_roles values(m,'MESS');
d:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','DESTINATION','name',n));
c:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','CONSIGNEE','name',n));
r:=public.impjo_catalog_api(a,'list',jsonb_build_object('kind','DESTINATION','q',n));assert (r->>'total')::int=1,'Destination missing or duplicated';
assert d->>'id'<>c->>'id','Kinds mixed';
perform public.impjo_catalog_api(a,'save',jsonb_build_object('kind','DESTINATION','name',lower(n)));
assert (public.impjo_catalog_api(a,'list',jsonb_build_object('kind','DESTINATION','q',n))->>'total')::int=1,'Duplicate case name';
insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA DROPDOWN','0811111111','QA',a,current_date) returning id into j;
insert into public.impjo_bls(job_id,number,consignee,destination) values(j,n,n,n);
perform public.impjo_catalog_api(a,'archive',jsonb_build_object('id',d->>'id'));
perform public.impjo_catalog_api(a,'archive',jsonb_build_object('id',c->>'id'));
assert (public.impjo_catalog_api(a,'list',jsonb_build_object('kind','DESTINATION','q',n))->>'total')::int=0,'Archived destination selectable';
assert exists(select 1 from public.impjo_bls where job_id=j and destination=n and consignee=n),'Historical values changed';
assert exists(select 1 from public.impjo_events where target_id=(d->>'id')::uuid and action='DESTINATION_ARCHIVED'),'Wrong destination audit';
denied:=false;begin perform public.impjo_catalog_api(m,'save',jsonb_build_object('kind','CONSIGNEE','name','NOT ALLOWED'));exception when insufficient_privilege then denied:=true;end;assert denied,'MESS catalog write';
end $$;
