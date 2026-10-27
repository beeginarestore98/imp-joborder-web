create or replace function public.impjo_documents(p_actor uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals;admin boolean;mess boolean;doc public.impjo_return_documents;recipient public.impjo_document_recipients;delivery public.impjo_document_deliveries;j public.impjo_jobs;b public.impjo_bls;key text;result jsonb;newlease uuid;
begin
 select * into person from public.impjo_principals where id=p_actor for share;
 if not found or person.state<>'APPROVED' or person.archived_at is not null then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select exists(select 1 from public.impjo_roles where principal_id=p_actor and role='ADMIN') and person.kind='STAFF',exists(select 1 from public.impjo_roles where principal_id=p_actor and role='MESS') and person.kind='LINE' into admin,mess;
 if p_action in('recipients','recipient_save','recipient_delete') then
  if not admin then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
  if p_action='recipient_delete' then
   if p_data->>'confirmed' is distinct from 'true' then raise exception 'DOCUMENT_CONFIRM_REQUIRED' using errcode='22023';end if;
   key:=lower(btrim(p_data->>'contact_name'));
   select * into recipient from public.impjo_document_recipients where contact_key=key for update;
   if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
   if recipient.updated_at is distinct from (p_data->>'version')::timestamptz then raise exception 'DOCUMENT_RECIPIENT_CHANGED' using errcode='22023';end if;
   delete from public.impjo_document_recipients where contact_key=key;
   insert into public.impjo_events(actor_id,action,detail) values(p_actor,'DOCUMENT_RECIPIENT_DELETED',jsonb_build_object('contact',key)::text);
  end if;
  if p_action='recipient_save' then
   key:=lower(btrim(p_data->>'contact_name'));
   if coalesce(length(key),0) not between 1 and 120 or coalesce(p_data->>'email','') !~ '^[A-Za-z0-9.!#$%&''*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$' or length(p_data->>'email')>254 then raise exception 'INVALID_RECIPIENT' using errcode='22023';end if;
   insert into public.impjo_document_recipients(contact_key,contact_name,email,enabled,updated_by) values(key,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),coalesce((p_data->>'enabled')::boolean,false),p_actor) on conflict(contact_key) do update set contact_name=excluded.contact_name,email=excluded.email,enabled=excluded.enabled,updated_by=p_actor,updated_at=clock_timestamp();
   insert into public.impjo_events(actor_id,action,detail) values(p_actor,'DOCUMENT_RECIPIENT_UPDATED',jsonb_build_object('contact',key,'enabled',p_data->'enabled')::text);
  end if;
  return jsonb_build_object('contacts',(select coalesce(jsonb_agg(c.contact order by c.contact),'[]') from(select distinct contact from public.impjo_jobs where archived_at is null union select name from public.impjo_catalog where kind='CONTACT' and archived_at is null union select contact_name from public.impjo_document_recipients)c),'recipients',coalesce((select jsonb_agg(to_jsonb(r) order by r.contact_name) from public.impjo_document_recipients r),'[]'));
 end if;
 if p_action='context' then
  select * into b from public.impjo_bls where id=(p_data->>'bl_id')::uuid;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 else
  if p_action='reserve' then
   if not mess then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
   select * into b from public.impjo_bls where id=(p_data->>'bl_id')::uuid;
  else
   select * into doc from public.impjo_return_documents where id=(p_data->>'id')::uuid for update;
   if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
   select * into b from public.impjo_bls where id=doc.bl_id;
  end if;
 end if;
 select * into j from public.impjo_jobs where id=b.job_id and archived_at is null for share;
 if not found or not public.impjo_visible_bl(p_actor,b.id) then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 select * into recipient from public.impjo_document_recipients where contact_key=lower(btrim(j.contact));
 if p_action='context' then
  return jsonb_build_object('contact',j.contact,'bl_number',b.number,'job_number',j.number,'can_upload',mess,'recipient',case when recipient.enabled then jsonb_build_object('email',recipient.email,'version',recipient.updated_at) else null end,'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'pages',d.pages,'bytes',d.bytes,'state',d.state,'mine',d.created_by=p_actor,'created_at',d.created_at,'deliveries',coalesce((select jsonb_agg(jsonb_build_object('channel',x.channel,'state',x.state,'error',x.error)) from public.impjo_document_deliveries x where x.document_id=d.id),'[]')) order by d.created_at desc) from public.impjo_return_documents d where d.bl_id=b.id and d.state<>'UPLOADING'),'[]'));
 end if;
 if p_action='file' then return jsonb_build_object('path',doc.object_path,'sha256',doc.sha256);end if;
 if not mess and not admin then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='reserve' then
  insert into public.impjo_return_documents(id,job_id,bl_id,created_by,object_path,sha256,pages,bytes) values((p_data->>'id')::uuid,j.id,b.id,p_actor,j.id::text||'/'||(p_data->>'id')||'.pdf',p_data->>'sha256',(p_data->>'pages')::int,(p_data->>'bytes')::int) on conflict(id) do nothing;
  select * into doc from public.impjo_return_documents where id=(p_data->>'id')::uuid for update;
  if doc.created_by<>p_actor or doc.bl_id<>b.id or doc.sha256<>p_data->>'sha256' then raise exception 'DOCUMENT_CONFLICT' using errcode='22023';end if;
  return jsonb_build_object('id',doc.id,'path',doc.object_path,'state',doc.state);
 end if;
 if doc.created_by<>p_actor and not admin then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 if p_action='complete' then
  update public.impjo_return_documents set state='READY' where id=doc.id and state='UPLOADING';
  if found then insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'RETURN_DOCUMENT_UPLOADED',b.id,jsonb_build_object('document_id',doc.id,'pages',doc.pages)::text);end if;
  return jsonb_build_object('id',doc.id,'state','READY');
 elsif p_action='submit' then
  if doc.state='UPLOADING' then raise exception 'DOCUMENT_NOT_READY' using errcode='22023';end if;
  if doc.state='READY' then
   if not coalesce(recipient.enabled,false) then raise exception 'DOCUMENT_RECIPIENT_REQUIRED' using errcode='22023';end if;
   if recipient.updated_at is distinct from (p_data->>'recipient_version')::timestamptz then raise exception 'DOCUMENT_RECIPIENT_CHANGED' using errcode='22023';end if;
   update public.impjo_return_documents set state='SUBMITTED',recipient_version=recipient.updated_at,email=recipient.email where id=doc.id;
   insert into public.impjo_document_deliveries(document_id,channel) values(doc.id,'email');
   insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'RETURN_DOCUMENT_SUBMITTED',b.id,doc.id::text);
  end if;
  return jsonb_build_object('id',doc.id,'state','SUBMITTED');
 elsif p_action='claim' then
  if not coalesce(recipient.enabled,false) or recipient.updated_at is distinct from doc.recipient_version then raise exception 'DOCUMENT_RECIPIENT_CHANGED' using errcode='22023';end if;
  select * into delivery from public.impjo_document_deliveries where document_id=doc.id and channel=p_data->>'channel' for update;
  if not found or delivery.state not in('PENDING','FAILED') then return jsonb_build_object('skip',true);end if;
  newlease:=gen_random_uuid();update public.impjo_document_deliveries set state='SENDING',lease=newlease,error='',updated_at=now() where document_id=doc.id and channel=delivery.channel;
  return jsonb_build_object('lease',newlease,'recipient',doc.email,'path',doc.object_path,'job_number',j.number,'bl_number',b.number,'contact',j.contact);
 elsif p_action='finish' then
  if p_data->>'state' not in('ACCEPTED','DELIVERED','FAILED','UNKNOWN') then raise exception 'INVALID_DELIVERY_STATE' using errcode='22023';end if;
  update public.impjo_document_deliveries set state=p_data->>'state',provider_id=left(p_data->>'provider_id',200),error=left(coalesce(p_data->>'error',''),100),updated_at=now() where document_id=doc.id and channel=p_data->>'channel' and lease=(p_data->>'lease')::uuid and state='SENDING';
  if not found then raise exception 'DOCUMENT_CONFLICT' using errcode='22023';end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'RETURN_DOCUMENT_DELIVERY',b.id,jsonb_build_object('document_id',doc.id,'channel',p_data->>'channel','state',p_data->>'state')::text);
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;
revoke all on function public.impjo_documents(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_documents(uuid,text,jsonb) to service_role;

