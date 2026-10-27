set local role service_role;do $$declare a uuid;p jsonb;r jsonb;n text:='QA ARCHIVED MONEY '||gen_random_uuid();begin
insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','QA ARCHIVED MONEY') returning id into a;insert into public.impjo_roles values(a,'OPERATOR');
p:=public.impjo_catalog_api(a,'save',jsonb_build_object('kind','PURPOSE','name',n,'requires_amount',true));perform public.impjo_catalog_api(a,'archive',jsonb_build_object('id',p->>'id'));
assert (public.impjo_catalog_api(a,'list',jsonb_build_object('kind','PURPOSE','q',n))->>'total')::int=0,'Archived purpose visible to new jobs';
r:=public.impjo_catalog_api(a,'list',jsonb_build_object('kind','PURPOSE','q',n,'retain_names',jsonb_build_array(n)));
assert (r->>'total')::int=1 and (r->'rows'->0->>'requires_amount')::boolean,'Historical money metadata missing';
assert impjo_private.job_amount(jsonb_build_object('purpose',n,'amount','125.50'))=125.50,'Historical decimal amount rejected';
end $$;
