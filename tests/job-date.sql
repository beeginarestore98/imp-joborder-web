begin;
set local role service_role;
do $$
declare a uuid; m uuid; j uuid; b uuid; result jsonb; denied boolean; today date:=(now() at time zone 'Asia/Bangkok')::date; i integer; day date;
begin
 insert into public.impjo_principals(kind,state,name) values('STAFF','APPROVED','TEST DATE ADMIN') returning id into a;
 insert into public.impjo_principals(kind,state,name) values('LINE','APPROVED','TEST DATE MESS') returning id into m;
 insert into public.impjo_roles values(a,'ADMIN'),(m,'MESS');
 for i in 1..6 loop
  day:=case when i in (1,2) then today when i in(3,4) then today-1 when i=5 then today+1 else today end;
  result:=public.impjo_api(a,'create',jsonb_build_object('job_date',day,'contact','DATE TEST','phone','000','purpose','ROLLBACK TEST','bls',jsonb_build_array(jsonb_build_object('number','DATE-'||i,'consignee','TEST','destination','TEST'))));
  j:=(result->>'id')::uuid;
  assert (select job_date=day from public.impjo_jobs where id=j),'Job date was replaced with record date';
  select id into b from public.impjo_bls where job_id=j;
  perform public.impjo_api(a,'assign',jsonb_build_object('bl_id',b,'role','MESS','principal_id',m));
  update public.impjo_bls set status=case when i in (2,4) then 'COMPLETED' else 'IN_PROGRESS' end where id=b;
  if i=6 then update public.impjo_jobs set job_date=null where id=j; end if;
 end loop;
 result:=public.impjo_api(m,'list');
 assert (result->>'total')::int=3,'MESS date filtering failed: today + unfinished past only';
 assert not exists(select 1 from jsonb_array_elements(result->'jobs') e where (e->>'job_date')::date>today or e->>'job_date' is null),'Future or undated job leaked into current list';
 assert (public.impjo_api(a,'list',jsonb_build_object('search','DATE-','current_only',true))->>'total')::int>=3,'Explicit current filter failed';
 denied:=false;begin perform public.impjo_api(a,'create','{"contact":"TEST","bls":[]}');exception when invalid_parameter_value then denied:=true;end;assert denied,'Missing job date accepted';
 denied:=false;begin perform public.impjo_api(a,'create','{"job_date":"2026-02-30","bls":[]}');exception when invalid_parameter_value then denied:=true;end;assert denied,'Impossible date accepted';
 denied:=false;begin perform public.impjo_api(m,'set_job_date',jsonb_build_object('id',j,'job_date',today));exception when insufficient_privilege then denied:=true;end;assert denied,'MESS changed job date';
 perform public.impjo_api(a,'set_job_date',jsonb_build_object('id',j,'job_date',today));
 assert exists(select 1 from public.impjo_events where target_id=j and action='JOB_DATE_CHANGED' and actor_id=a),'Job date audit missing';
 assert (public.impjo_api(m,'list')->>'total')::int=4,'Manual date assignment did not reveal current job';
end $$;
rollback;
select 'PASS: separate job date, Thai current day, overdue filtering, future/undated exclusion, manual date assignment, validation and authorization. All fixtures rolled back.' as result;