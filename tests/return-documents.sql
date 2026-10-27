-- Run after the proposal SQL within a transaction, then roll everything back.
set local role service_role;
do $$
declare m uuid;o uuid;a uuid;j uuid;b uuid;d uuid:=gen_random_uuid();r jsonb;version text;lease text;denied boolean;
begin
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA DOC MESS') returning id into m;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA DOC OUT') returning id into o;
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA DOC ADMIN') returning id into a;
 insert into public.impjo_roles values(m,'MESS'),(o,'OUTSOURCE'),(a,'ADMIN');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA RETURN DOC','000','QA',a,current_date) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination,status) values(j,'QA-DOC-BL','QA','QA','COMPLETED') returning id into b;
 denied:=false;begin perform public.impjo_documents(o,'reserve',jsonb_build_object('id',d,'bl_id',b));exception when insufficient_privilege then denied:=true;end;assert denied,'OUTSOURCE uploaded';
 r:=public.impjo_documents(m,'reserve',jsonb_build_object('id',d,'bl_id',b,'pages',2,'bytes',100,'sha256',repeat('a',64)));assert r->>'state'='UPLOADING','No upload reservation';
 perform public.impjo_documents(m,'complete',jsonb_build_object('id',d));
 assert (select status from public.impjo_bls where id=b)='COMPLETED','Document changed business status';
 denied:=false;begin perform public.impjo_documents(m,'submit',jsonb_build_object('id',d));exception when sqlstate '22023' then denied:=true;end;assert denied,'Sent without recipient';
 denied:=false;begin perform public.impjo_documents(m,'recipient_save','{}');exception when insufficient_privilege then denied:=true;end;assert denied,'MESS edited recipients';
 perform public.impjo_documents(a,'recipient_save',jsonb_build_object('contact_name','QA RETURN DOC','email','qa@example.invalid','enabled',true));
 r:=public.impjo_documents(m,'context',jsonb_build_object('bl_id',b));version:=r->'recipient'->>'version';assert r->>'can_upload'='true','MESS late documents denied';
 denied:=false;begin perform public.impjo_documents(m,'submit',jsonb_build_object('id',d,'recipient_version','2000-01-01'));exception when sqlstate '22023' then denied:=true;end;assert denied,'Recipient confirmation stale';
 perform public.impjo_documents(m,'submit',jsonb_build_object('id',d,'recipient_version',version));assert (select count(*) from public.impjo_document_deliveries where document_id=d)=1,'Missing email delivery';
 r:=public.impjo_documents(m,'claim',jsonb_build_object('id',d,'channel','email'));lease:=r->>'lease';assert lease is not null,'No lease';
 r:=public.impjo_documents(m,'claim',jsonb_build_object('id',d,'channel','email'));assert r->>'skip'='true','Duplicate claim';
 perform public.impjo_documents(m,'finish',jsonb_build_object('id',d,'channel','email','lease',lease,'state','UNKNOWN','error','QA timeout'));
 r:=public.impjo_documents(m,'claim',jsonb_build_object('id',d,'channel','email'));assert r->>'skip'='true','Ambiguous delivery retried';
 update public.impjo_principals set state='DISABLED' where id=m;
 denied:=false;begin perform public.impjo_documents(m,'file',jsonb_build_object('id',d));exception when insufficient_privilege then denied:=true;end;assert denied,'Disabled user read PDF';
 assert not has_function_privilege('anon','public.impjo_documents(uuid,text,jsonb)','EXECUTE'),'Anonymous executes RPC';
 assert not has_function_privilege('authenticated','public.impjo_documents(uuid,text,jsonb)','EXECUTE'),'Auth bypasses backend';
 delete from public.impjo_bls where id=b;
 delete from public.impjo_jobs where id=j;
 assert not exists(select 1 from public.impjo_return_documents where id=d),'Job deletion blocked or metadata orphaned';
end $$;
