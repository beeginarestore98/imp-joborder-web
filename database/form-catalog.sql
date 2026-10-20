create table public.impjo_catalog(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('CONTACT','PURPOSE','SHIPPING')),
 name text not null check(length(btrim(name)) between 1 and 200),phone text not null default '' check(length(phone)<=30),
 requires_amount boolean not null default false,source_url text,archived_at timestamptz,
 created_by uuid references public.impjo_principals(id),created_at timestamptz not null default now()
);
create unique index impjo_catalog_name on public.impjo_catalog(kind,lower(btrim(name)));
alter table public.impjo_catalog enable row level security;
revoke all on public.impjo_catalog from public,anon,authenticated;
grant all on public.impjo_catalog to service_role;
alter table public.impjo_jobs add column amount numeric(14,2) check(amount>=0 and amount<=9999999999.99);
insert into public.impjo_catalog(kind,name,requires_amount) values('PURPOSE','รับ D/O',false),('PURPOSE','ตามใบมัดจำตู้',true),('PURPOSE','ตามใบเสร็จ',true);
-- Existing job snapshots remain unchanged; most recent phone initializes each Contact.
insert into public.impjo_catalog(kind,name,phone)
 select 'CONTACT',contact,phone from(select distinct on(lower(btrim(contact))) btrim(contact) contact,btrim(phone) phone from public.impjo_jobs where length(btrim(contact)) between 1 and 120 and length(btrim(phone)) between 1 and 30 and archived_at is null order by lower(btrim(contact)),created_at desc,id)t;

create function public.impjo_catalog_api(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals; item public.impjo_catalog; k text:=p_data->>'kind'; n text:=btrim(p_data->>'name'); ph text:=btrim(coalesce(p_data->>'phone','')); page int:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000)); result jsonb;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if not found or person.kind<>'STAFF' or person.state<>'APPROVED' or person.archived_at is not null or not exists(select 1 from public.impjo_roles where principal_id=p_actor and role in ('ADMIN','OPERATOR')) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='list' then
  if k is null or k not in('CONTACT','PURPOSE','SHIPPING') then raise exception 'INVALID_CATALOG' using errcode='22023';end if;
  with matched as(select * from public.impjo_catalog where kind=k and archived_at is null and (coalesce(p_data->>'q','')='' or strpos(lower(name||' '||phone),lower(left(p_data->>'q',200)))>0)),
  paged as(select * from matched order by lower(name),name,id limit 50 offset ((page-1)*50))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p) order by lower(p.name),p.name,p.id) from paged p),'[]'),'total',(select count(*) from matched)) into result;
  return result;
 elsif p_action='save' then
  if k is null or k not in('CONTACT','PURPOSE') or n is null or length(n) not between 1 and (case when k='CONTACT' then 120 else 200 end) or (k='CONTACT' and length(ph) not between 1 and 30) then raise exception 'INVALID_CATALOG' using errcode='22023';end if;
  insert into public.impjo_catalog(kind,name,phone,requires_amount,created_by) values(k,n,case when k='CONTACT' then ph else '' end,case when k='PURPOSE' then coalesce((p_data->>'requires_amount')::boolean,false) else false end,p_actor)
   on conflict(kind,lower(btrim(name))) do update set phone=excluded.phone,archived_at=null returning * into item;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'CATALOG_SAVED',item.id,jsonb_build_object('kind',k,'name',item.name)::text);
  return to_jsonb(item);
 elsif p_action='archive' then
  select * into item from public.impjo_catalog where id=(p_data->>'id')::uuid and kind='CONTACT' and archived_at is null for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  update public.impjo_catalog set archived_at=now() where id=item.id;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'CONTACT_ARCHIVED',item.id,item.name);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;
revoke all on function public.impjo_catalog_api(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_catalog_api(uuid,text,jsonb) to service_role;

create function impjo_private.job_amount(p_data jsonb) returns numeric language plpgsql stable set search_path='' as $$
declare value text:=nullif(btrim(p_data->>'amount'),''); required boolean;
begin
 select coalesce(bool_or(requires_amount),false) into required from public.impjo_catalog where kind='PURPOSE' and lower(btrim(name))=lower(btrim(p_data->>'purpose'));
 if value is null then if required then raise exception 'AMOUNT_REQUIRED' using errcode='22023';end if;return null;end if;
 if value !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT' using errcode='22023';end if;
 return value::numeric;
end $$;
revoke all on function impjo_private.job_amount(jsonb) from public,anon,authenticated;
grant execute on function impjo_private.job_amount(jsonb) to service_role;

do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='insert into public.impjo_jobs(job_date,contact,phone,purpose,laem,notes,created_by)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected create columns';end if;
 definition:=replace(definition,needle,'insert into public.impjo_jobs(job_date,contact,phone,purpose,laem,notes,created_by,amount)');
 needle:='coalesce(p_data->>''notes'',''''),p_actor) returning id into v_job;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected create values';end if;
 execute replace(definition,needle,'coalesce(p_data->>''notes'',''''),p_actor,impjo_private.job_amount(p_data)) returning id into v_job;');
 definition:=pg_get_functiondef('public.impjo_manage(uuid,text,jsonb)'::regprocedure);
 needle:='purpose=btrim(p_data->>''purpose''),laem=';
 if strpos(definition,needle)=0 then raise exception 'Unexpected edit values';end if;
 definition:=replace(definition,needle,'purpose=btrim(p_data->>''purpose''),amount=impjo_private.job_amount(p_data),laem=');
 needle:='j.phone,j.purpose,j.laem';
 if strpos(definition,needle)=0 then raise exception 'Unexpected export fields';end if;
 execute replace(definition,needle,'j.phone,j.purpose,j.amount,j.laem');
end $migration$;

