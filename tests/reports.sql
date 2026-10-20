begin;
do $$
declare a uuid;o uuid;m uuid;j uuid;b uuid;subject text:='U'||replace(gen_random_uuid()::text,'-','');contact text:='QA REPORT '||gen_random_uuid();d date:=(now() at time zone 'Asia/Bangkok')::date;hash text;r jsonb;item jsonb;denied boolean;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA REPORT ADMIN') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA REPORT RECIPIENT') returning id into o;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA REPORT MESS') returning id into m;
 insert into public.impjo_roles values(a,'ADMIN'),(o,'OUTSOURCE'),(m,'MESS');
 insert into public.impjo_line_identities(provider,subject,principal_id) values('2012071986',subject,o),('2012071986','U'||replace(gen_random_uuid()::text,'-',''),m);
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values(contact,'000','REPORT TEST',a,d) returning id into j;
 insert into public.impjo_bls(job_id,number,consignee,destination,status) select j,'QA-BL-'||n,'QA','QA',case when n<=3 then 'COMPLETED' when n=4 then 'ISSUE_REPORTED' when n<=7 then 'IN_PROGRESS' else 'PENDING_HANDOVER' end from generate_series(1,9)n;
 update public.impjo_report_settings set enabled=false where id;
 assert impjo_private.enqueue_evening_reports(d)=0,'Disabled reports were queued';
 perform public.impjo_reports(a,'recipient',jsonb_build_object('contact_name',contact,'recipient_id',o,'enabled',true));
 perform public.impjo_reports(a,'enabled','{"enabled":true}');
 perform impjo_private.enqueue_evening_reports(d);
 assert (select count(*) from public.impjo_report_outbox where contact_key=lower(contact) and report_date=d)=2,'Report did not page all BLs';
 assert (select (payload->'summary'->>'total')::int=9 from public.impjo_report_outbox where contact_key=lower(contact) and page=1),'Report count wrong';
 assert (select (payload->'summary'->>'completed')::int=3 from public.impjo_report_outbox where contact_key=lower(contact) and page=1),'Completed count wrong';
 perform impjo_private.enqueue_evening_reports(d);
 assert (select count(*) from public.impjo_report_outbox where contact_key=lower(contact))=2,'Duplicate daily report queued';
 select token_hash into hash from public.impjo_report_settings where id;
 denied:=false;begin perform public.impjo_report_claim(repeat('z',64));exception when invalid_authorization_specification then denied:=true;end;assert denied,'Invalid scheduler token accepted';
 r:=public.impjo_report_claim(hash);
 select x into item from jsonb_array_elements(r)x where x->'payload'->>'contact_name'=contact limit 1;
 assert item is not null,'Worker did not claim report';
 assert public.impjo_report_destination((item->>'id')::uuid,(item->>'lease')::uuid)=subject,'Wrong LINE recipient';
 assert public.impjo_report_destination((item->>'id')::uuid,gen_random_uuid()) is null,'Wrong lease obtained destination';
 perform public.impjo_reports(a,'recipient',jsonb_build_object('contact_name',contact,'recipient_id',m,'enabled',true));
 assert public.impjo_report_destination((item->>'id')::uuid,(item->>'lease')::uuid) is null,'Changed recipient retained queued access';
 perform impjo_private.enqueue_evening_reports(d);
 assert exists(select 1 from public.impjo_report_outbox where recipient_id=m and contact_key=lower(contact)),'Approved MESS read-all recipient did not receive its configured Contact';
 denied:=false;begin perform public.impjo_reports(o,'settings');exception when insufficient_privilege then denied:=true;end;assert denied,'Nonadmin configured reports';
 assert not has_table_privilege('anon','public.impjo_report_settings','SELECT'),'Anonymous scheduler secret access';
 assert not has_function_privilege('authenticated','public.impjo_report_claim(text)','EXECUTE'),'Public worker RPC access';
end $$;
rollback;
select 'PASS: report opt-in, date/status grouping, all BL pages, daily deduplication, token authentication, recipient/lease revalidation and approved MESS shared visibility; no messages sent, fixtures rolled back.' as result;

