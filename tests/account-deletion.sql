begin;
-- Disposable Auth fixtures only, always rolled back.
select set_config('impjo.qa_uid',gen_random_uuid()::text,true),set_config('impjo.qa_email','qa-delete-'||gen_random_uuid()::text||'@example.invalid',true);
insert into auth.users(id,email,email_confirmed_at) values(current_setting('impjo.qa_uid')::uuid,current_setting('impjo.qa_email'),now());
set local role service_role;
do $$
declare a uuid;o uuid;l uuid;s uuid;j uuid;r jsonb;denied boolean;qa_subject text;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA DELETE ADMIN') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA DELETE OP') returning id into o;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','QA DELETE LINE') returning id into l;
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA DELETE STAFF') returning id into s;
 perform set_config('impjo.qa_admin',a::text,true);perform set_config('impjo.qa_staff',s::text,true);
 insert into public.impjo_roles values(a,'ADMIN'),(o,'OPERATOR'),(l,'MESS'),(s,'OPERATOR');
 qa_subject:='U'||replace(l::text,'-','');
 insert into public.impjo_line_identities values('2005629037',qa_subject,l);
 insert into public.impjo_staff_identities values(current_setting('impjo.qa_uid')::uuid,s);
 insert into public.impjo_sessions(token_hash,principal_id,expires_at) values(repeat('e',64),l,now()+interval '1 hour');
 insert into public.impjo_jobs(contact,phone,purpose,created_by,job_date) values('QA DELETE','000','QA',s,current_date) returning id into j;
 denied:=false;begin perform public.impjo_account_admin(o,'prepare',l);exception when insufficient_privilege then denied:=true;end;assert denied,'Operator deleted account';
 denied:=false;begin perform public.impjo_account_admin(a,'prepare',a);exception when insufficient_privilege then denied:=true;end;assert denied,'Admin deleted self';
 perform public.impjo_account_admin(a,'prepare',l);perform public.impjo_account_admin(a,'finish',l);
 assert not exists(select 1 from public.impjo_line_identities where principal_id=l),'LINE identity retained';
 assert not exists(select 1 from public.impjo_sessions where principal_id=l),'LINE session retained';
 assert not exists(select 1 from public.impjo_roles where principal_id=l),'Role retained';
 assert (select name='บัญชีที่ลบแล้ว' from public.impjo_principals where id=l),'PII name retained';
 denied:=false;begin perform public.impjo_manage(a,'restore_account',jsonb_build_object('id',l));exception when insufficient_privilege then denied:=true;end;assert denied,'Deleted actor restored';
 perform public.impjo_line_session(qa_subject,repeat('f',64));
 assert exists(select 1 from public.impjo_line_identities i join public.impjo_principals p on p.id=i.principal_id where i.subject=qa_subject and p.id<>l and p.state='PENDING'),'LINE could not register fresh';
 r:=public.impjo_account_admin(a,'prepare',s);assert r->>'auth_user_id'=current_setting('impjo.qa_uid'),'Auth identity mismatch';
 denied:=false;begin perform public.impjo_account_admin(a,'finish',s);exception when raise_exception then denied:=sqlerrm='ACCOUNT_DELETE_PENDING';end;assert denied,'Reported success before Auth deletion';
 denied:=false;begin perform public.impjo_staff_actor(current_setting('impjo.qa_uid')::uuid);exception when invalid_authorization_specification then denied:=true;end;assert denied,'Pending Auth deletion recreated app identity';
 denied:=false;begin perform public.impjo_register_pending(current_setting('impjo.qa_uid')::uuid);exception when invalid_authorization_specification then denied:=true;end;assert denied,'Duplicate signup bypassed deletion';
 assert exists(select 1 from public.impjo_jobs where id=j and created_by=s),'Existing job removed';
 assert (public.impjo_account_admin(a,'confirmation',o)->'roles'->>0)='OPERATOR','Saved role readback wrong';
 perform public.impjo_api(a,'approve',jsonb_build_object('id',o,'name','QA CHANGED ROLE','role','ADMIN','state','APPROVED'));
 r:=public.impjo_account_admin(a,'confirmation',o);
 assert r->>'name'='QA CHANGED ROLE' and r->'roles'->>0='ADMIN' and r->>'state'='APPROVED','Confirmation did not reflect saved role change';
 assert not has_function_privilege('authenticated','public.impjo_account_admin(uuid,text,uuid)','EXECUTE'),'Client can call deletion RPC';
end $$;
reset role;
delete from auth.users where id=current_setting('impjo.qa_uid')::uuid;
set local role service_role;
select public.impjo_account_admin(current_setting('impjo.qa_admin')::uuid,'finish',current_setting('impjo.qa_staff')::uuid);
do $$begin
 assert (select completed_at is not null and auth_user_id is null from public.impjo_account_deletions where principal_id=current_setting('impjo.qa_staff')::uuid),'Deletion not finalized';
 assert (select count(*)=1 from public.impjo_events where target_id=current_setting('impjo.qa_staff')::uuid and action='ACCOUNT_DELETED'),'Deletion audit missing';
end $$;
reset role;
-- The same email can be registered again with a new Auth identity.
insert into auth.users(id,email,email_confirmed_at) values(gen_random_uuid(),current_setting('impjo.qa_email'),now());
rollback;

