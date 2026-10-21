-- Service-only LINE OPERATOR browse and atomic multi-B/L confirmation.
create or replace function public.impjo_operator_chat(p_actor uuid,p_subject text,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare d public.impjo_events; payload jsonb; selected jsonb:='[]'; items jsonb; result jsonb; item jsonb; row_bl record; key text; page int; draft bigint; wanted uuid; target text; issue text; changed int:=0;
begin
 perform 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=p_actor and p.state='APPROVED' and p.archived_at is null and p.kind in ('STAFF','LINE') and r.role='OPERATOR' for share of p;
 if not found or public.impjo_operator_actor(p_subject) is distinct from p_actor then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 page:=greatest(1,least(coalesce((p_data->>'page')::int,1),100000));key:=coalesce(p_data->>'key','');
 if p_action='contacts' then
  with contacts as(select md5(lower(btrim(j.contact))) as key,min(j.contact) as contact,count(*) as bl_count from public.impjo_jobs j join public.impjo_bls b on b.job_id=j.id where j.archived_at is null and public.impjo_visible_bl(p_actor,b.id) group by lower(btrim(j.contact))),
  paged as(select c.* from contacts c order by lower(c.contact),c.key limit 10 offset((page-1)*10))
  select jsonb_build_object('total',(select count(*) from contacts),'contacts',coalesce((select jsonb_agg(to_jsonb(p) order by lower(p.contact),p.key) from paged p),'[]'),'page',page) into result;
  return result;
 end if;
 if p_action in ('toggle','page','propose','confirm') then
  select * into d from public.impjo_events where id=(p_data->>'draft')::bigint and actor_id=p_actor and action in ('CHAT_OPERATOR_SELECTION','CHAT_OPERATOR_BATCH_PROPOSED') for update;
  if not found or d.created_at<now()-interval '10 minutes' then raise exception 'CHAT_EXPIRED' using errcode='22023';end if;
  payload:=d.detail::jsonb;
  if payload->>'subject' is distinct from p_subject then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  key:=payload->>'key';selected:=payload->'selected';page:=greatest(1,coalesce((p_data->>'page')::int,(payload->>'page')::int,1));
  if p_action<>'confirm' and d.action<>'CHAT_OPERATOR_SELECTION' then raise exception 'CHAT_EXPIRED' using errcode='22023';end if;
 end if;
 if p_action='confirm' then
  if d.action<>'CHAT_OPERATOR_BATCH_PROPOSED' or exists(select 1 from public.impjo_events where actor_id=p_actor and action='CHAT_OPERATOR_BATCH_APPLIED' and detail=d.id::text) then raise exception 'CHAT_EXPIRED' using errcode='22023';end if;
  target:=payload->>'status';issue:=payload->>'issue';items:=payload->'items';
  if jsonb_array_length(items) not between 1 and 20 or target not in ('PENDING_HANDOVER','IN_PROGRESS','ISSUE_REPORTED','COMPLETED') then raise exception 'INVALID_BATCH' using errcode='22023';end if;
  -- Match the normal API's lock order: jobs first, then B/Ls, both in stable order.
  perform 1 from public.impjo_jobs j where j.id in(select b.job_id from public.impjo_bls b join jsonb_array_elements(items) x on b.id=(x->>'id')::uuid) order by j.id for share;
  perform 1 from public.impjo_bls b join jsonb_array_elements(items) x on b.id=(x->>'id')::uuid order by b.id for update of b;
  for item in select * from jsonb_array_elements(items) loop
   select b.status into row_bl from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where b.id=(item->>'id')::uuid and j.archived_at is null and public.impjo_visible_bl(p_actor,b.id);
   if not found or row_bl.status is distinct from item->>'status' then raise exception 'STALE_STATUS' using errcode='22023';end if;
  end loop;
  for item in select * from jsonb_array_elements(items) loop
   perform public.impjo_api(p_actor,'status',jsonb_build_object('bl_id',item->>'id','expected_status',item->>'status','status',target,'detail',case when target='ISSUE_REPORTED' then issue else 'อัปเดตหลายรายการผ่าน LINE OPERATOR' end));
   if item->>'status'<>target then changed:=changed+1;end if;
  end loop;
  insert into public.impjo_events(actor_id,action,detail) values(p_actor,'CHAT_OPERATOR_BATCH_APPLIED',d.id::text);
  return jsonb_build_object('ok',true,'changed',changed,'total',jsonb_array_length(items),'status',target,'items',items);
 end if;
 if p_action='toggle' then
  wanted:=(p_data->>'bl_id')::uuid;
  if exists(select 1 from jsonb_array_elements_text(selected) x where x::uuid=wanted) then
   select coalesce(jsonb_agg(x),'[]') into selected from jsonb_array_elements_text(selected) x where x::uuid<>wanted;
  else
   if jsonb_array_length(selected)>=20 then raise exception 'BATCH_LIMIT' using errcode='22023';end if;
   perform 1 from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where b.id=wanted and j.archived_at is null and md5(lower(btrim(j.contact)))=key and public.impjo_visible_bl(p_actor,b.id);
   if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
   selected:=selected||jsonb_build_array(wanted);
  end if;
 end if;
 if p_action='propose' then
  target:=p_data->>'status';issue:=coalesce(p_data->>'issue','');
  if jsonb_array_length(selected) not between 1 and 20 or target is null or target not in ('PENDING_HANDOVER','IN_PROGRESS','ISSUE_REPORTED','COMPLETED') then raise exception 'INVALID_BATCH' using errcode='22023';end if;
  if target='ISSUE_REPORTED' and issue not in ('แจ้งวันนัดใหม่','แก้ไขเอกสาร') then raise exception 'ISSUE_DETAIL_REQUIRED' using errcode='22023';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'number',b.number,'job_number',j.number,'status',b.status) order by j.number,b.number,b.id),'[]') into items from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id join jsonb_array_elements_text(selected) x on b.id=x::uuid where j.archived_at is null and md5(lower(btrim(j.contact)))=key and public.impjo_visible_bl(p_actor,b.id);
  if jsonb_array_length(items)<>jsonb_array_length(selected) then raise exception 'STALE_STATUS' using errcode='22023';end if;
  insert into public.impjo_events(actor_id,action,detail) values(p_actor,'CHAT_OPERATOR_BATCH_PROPOSED',jsonb_build_object('subject',p_subject,'key',key,'selected',selected,'items',items,'status',target,'issue',issue)::text) returning id into draft;
  return jsonb_build_object('draft',draft,'items',items,'status',target,'issue',issue);
 end if;
 if p_action not in ('bls','start','toggle','page') then raise exception 'UNKNOWN_ACTION' using errcode='22023';end if;
 if p_action in ('start','toggle','page') then
  insert into public.impjo_events(actor_id,action,detail) values(p_actor,'CHAT_OPERATOR_SELECTION',jsonb_build_object('subject',p_subject,'key',key,'selected',selected,'page',page)::text) returning id into draft;
 end if;
 with eligible as(select b.id,b.number,b.destination,b.status,j.number as job_number,j.contact,j.purpose,j.amount,j.job_date from public.impjo_bls b join public.impjo_jobs j on j.id=b.job_id where j.archived_at is null and md5(lower(btrim(j.contact)))=key and public.impjo_visible_bl(p_actor,b.id)),
 paged as(select * from eligible order by job_date desc nulls last,job_number,number,id limit 5 offset((page-1)*5))
 select jsonb_build_object('total',(select count(*) from eligible),'contact',(select contact from eligible limit 1),'bls',coalesce((select jsonb_agg(to_jsonb(p) order by job_date desc nulls last,job_number,number,id) from paged p),'[]'),'purpose_summary',coalesce((select jsonb_agg(to_jsonb(s) order by purpose) from(select purpose,count(*) as jobs,sum(amount) as amount from(select distinct j.id,j.purpose,j.amount from public.impjo_jobs j join eligible b on b.job_number=j.number)s group by purpose)s),'[]'),'draft',draft,'selected',selected,'page',page,'key',key) into result;
 return result;
end $$;
revoke all on function public.impjo_operator_chat(uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_operator_chat(uuid,text,text,jsonb) to service_role;
