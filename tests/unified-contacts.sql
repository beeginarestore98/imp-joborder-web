set local role service_role;do $$ declare a uuid;m uuid;r jsonb;v text;denied boolean;n text:='QA UNIFIED '||gen_random_uuid();begin
insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA UNIFIED ADMIN') returning id into a;
insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA UNIFIED MESS') returning id into m;
insert into public.impjo_roles values(a,'ADMIN'),(m,'MESS');
denied:=false;begin perform public.impjo_documents(a,'contacts_save',jsonb_build_object('contact_name',n,'phone','000','email','INVALID','enabled',true));exception when sqlstate '22023' then denied:=true;end;assert denied,'Invalid email accepted';
assert not exists(select 1 from public.impjo_catalog where name=n),'Phone saved despite email failure';
perform public.impjo_documents(a,'contacts_save',jsonb_build_object('contact_name',n,'phone','000','email','qa@example.invalid','enabled',true));
assert exists(select 1 from public.impjo_catalog where name=n and phone='000' and archived_at is null),'Contact missing';
select updated_at::text into v from public.impjo_document_recipients where contact_key=lower(n);assert v is not null,'Email missing';
r:=public.impjo_documents(a,'contacts_list',jsonb_build_object('q',n));assert (r->>'total')::int=1,'List duplicated';assert r->'rows'->0->>'phone'='000','Phone not joined';assert r->'rows'->0->>'email'='qa@example.invalid','Email not joined';
denied:=false;begin perform public.impjo_documents(m,'contacts_delete',jsonb_build_object('contact_name',n,'recipient_version',v,'confirmed',true));exception when insufficient_privilege then denied:=true;end;assert denied,'MESS removed contact';
denied:=false;begin perform public.impjo_documents(a,'contacts_delete',jsonb_build_object('contact_name',n,'confirmed',true));exception when sqlstate '22023' then denied:=true;end;assert denied,'Stale deletion accepted';
assert exists(select 1 from public.impjo_catalog where name=n and archived_at is null),'Stale deletion archived contact';
perform public.impjo_documents(a,'contacts_delete',jsonb_build_object('contact_name',n,'recipient_version',v,'confirmed',true));
assert not exists(select 1 from public.impjo_catalog where name=n and archived_at is null),'Contact still active';assert not exists(select 1 from public.impjo_document_recipients where contact_key=lower(n)),'Email retained';
perform public.impjo_documents(a,'contacts_save',jsonb_build_object('contact_name',n,'phone','111','email',''));
assert exists(select 1 from public.impjo_catalog where name=n and phone='111' and archived_at is null),'Recreate failed';
end $$;