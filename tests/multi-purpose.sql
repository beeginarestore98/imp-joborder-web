set local role service_role;do $$ declare a uuid;p jsonb;r jsonb;denied boolean;n text:='QA PURPOSE '||gen_random_uuid();begin
insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA PURPOSE OPERATOR') returning id into a;insert into public.impjo_roles values(a,'OPERATOR');
p:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','PURPOSE','name',n,'requires_amount',true));
denied:=false;begin perform impjo_private.job_amount(jsonb_build_object('purpose','รับ D/O'||chr(10)||n));exception when sqlstate '22023' then denied:=true;end;assert denied,'Combined money purpose bypassed amount';
assert impjo_private.job_amount(jsonb_build_object('purpose','รับ D/O'||chr(10)||n,'amount','1234.50'))=1234.50,'Decimal total failed';
perform public.impjo_catalog_api(a,'archive',jsonb_build_object('id',p->>'id'));
assert exists(select 1 from public.impjo_catalog where id=(p->>'id')::uuid and archived_at is not null),'Purpose removal failed';
assert impjo_private.job_amount(jsonb_build_object('purpose',n,'amount','12.00'))=12,'Legacy purpose failed';
denied:=false;begin perform public.impjo_catalog_api(a,'save',jsonb_build_object('kind','PURPOSE','name','bad'||chr(10)||'name'));exception when sqlstate '22023' then denied:=true;end;assert denied,'Newline purpose accepted';
end $$;