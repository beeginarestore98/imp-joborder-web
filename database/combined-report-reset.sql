alter table public.impjo_bls add column report_outcome text check(report_outcome in('COMPLETED','ISSUE_REPORTED')),add column report_detail text not null default '' check(length(report_detail)<=2000);
alter table public.impjo_status_notifications add column document_id uuid references public.impjo_return_documents(id) on delete set null;
create index impjo_status_notification_document on public.impjo_status_notifications(document_id);
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('public.impjo_queue_status_email()'::regprocedure);
 definition:=replace(definition,$old$'status',new.after_status,'issueDetail',case when new.after_status='ISSUE_REPORTED' then new.detail else '' end$old$,$new$'status',coalesce(b.report_outcome,new.after_status),'issueDetail',case when coalesce(b.report_outcome,new.after_status)='ISSUE_REPORTED' then coalesce(nullif(b.report_detail,''),new.detail) else '' end$new$);
 execute definition;
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 definition:=replace(definition,'declare v_email_event bigint;','declare v_email_event bigint;v_report_requested text;v_return_document public.impjo_return_documents;v_mail public.impjo_status_notifications;');
 needle:='update public.impjo_bls set status=v_new where id=v_bl;';
 if strpos(definition,needle)=0 then raise exception 'Unexpected status update';end if;
 definition:=replace(definition,needle,$new$if exists(select 1 from public.impjo_events where target_id=v_bl and action='REPORT_RESET_FILES_PENDING') then raise exception 'REPORT_RESET_BUSY' using errcode='22023';end if;
  v_report_requested:=v_new;
  if v_person.kind='LINE' and 'MESS'=any(v_roles) then
   update public.impjo_bls set report_outcome=v_report_requested,report_detail=case when v_report_requested='ISSUE_REPORTED' then coalesce(p_data->>'detail','') else '' end where id=v_bl;
   v_new:='COMPLETED';
  else
   update public.impjo_bls set report_outcome=null,report_detail='' where id=v_bl;
  end if;
  update public.impjo_bls set status=v_new where id=v_bl;$new$);
 needle:=$old$return jsonb_build_object('ok',true,'notification_id',(select id from public.impjo_status_notifications where event_id=v_email_event));$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected notification response';end if;
 definition:=replace(definition,needle,$new$if nullif(p_data->>'recipient_version','') is not null and not exists(select 1 from public.impjo_status_notifications where event_id=v_email_event and recipient_version=(p_data->>'recipient_version')::timestamptz and state='PENDING') then raise exception 'DOCUMENT_RECIPIENT_CHANGED' using errcode='22023';end if;
  if nullif(p_data->>'document_id','') is not null then
   if v_person.kind<>'LINE' or not ('MESS'=any(v_roles)) then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
   select * into v_return_document from public.impjo_return_documents where id=(p_data->>'document_id')::uuid and bl_id=v_bl and created_by=p_actor and state='READY' for update;
   if not found then raise exception 'DOCUMENT_CONFLICT' using errcode='22023';end if;
   select * into v_mail from public.impjo_status_notifications where event_id=v_email_event and state='PENDING';
   if not found then raise exception 'DOCUMENT_RECIPIENT_REQUIRED' using errcode='22023';end if;
   update public.impjo_return_documents set state='SUBMITTED',email=v_mail.recipient_email,recipient_version=v_mail.recipient_version where id=v_return_document.id;
   insert into public.impjo_document_deliveries(document_id,channel) values(v_return_document.id,'email');
   update public.impjo_status_notifications set document_id=v_return_document.id where id=v_mail.id;
  end if;
  return jsonb_build_object('ok',true,'status',v_new,'report_outcome',(select report_outcome from public.impjo_bls where id=v_bl),'notification_id',(select id from public.impjo_status_notifications where event_id=v_email_event));$new$);
 -- Closed reports with an issue remain visible in dashboard issue totals.
 definition:=replace(definition,$old$b.status='ISSUE_REPORTED'$old$,$new$(b.status='ISSUE_REPORTED' or b.report_outcome='ISSUE_REPORTED')$new$);
 execute definition;
 definition:=pg_get_functiondef('public.impjo_status_mail(uuid,text,jsonb)'::regprocedure);
 needle:=$old$return n.payload||jsonb_build_object('to',n.recipient_email,'documentId',n.id,'lease',newlease);$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected status mail claim';end if;
 definition:=replace(definition,needle,$new$if n.document_id is not null then update public.impjo_document_deliveries set state='SENDING',lease=newlease,updated_at=now() where document_id=n.document_id and channel='email';end if;
  return n.payload||jsonb_build_object('to',n.recipient_email,'documentId',n.id,'lease',newlease,'document_path',(select object_path from public.impjo_return_documents where id=n.document_id));$new$);
 needle:=$old$insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'STATUS_EMAIL_RESULT'$old$;
 definition:=replace(definition,needle,$new$if n.document_id is not null then update public.impjo_document_deliveries set state=p_data->>'state',provider_id=left(p_data->>'provider_id',200),error=left(coalesce(p_data->>'error',''),100),updated_at=now() where document_id=n.document_id and channel='email' and lease=(p_data->>'lease')::uuid;end if;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'STATUS_EMAIL_RESULT'$new$);
 execute definition;
 definition:=pg_get_functiondef('public.impjo_documents(uuid,text,jsonb)'::regprocedure);
 definition:=replace(definition,$old$if p_action='reserve' then
  insert into public.impjo_return_documents$old$,$new$if p_action='reserve' then
  perform 1 from public.impjo_bls where id=b.id for update;
  if exists(select 1 from public.impjo_events where target_id=b.id and action='REPORT_RESET_FILES_PENDING') then raise exception 'REPORT_RESET_BUSY' using errcode='22023';end if;
  insert into public.impjo_return_documents$new$);
 definition:=replace(definition,$old$elsif p_action='claim' then$old$,$new$elsif p_action='claim' then
  if exists(select 1 from public.impjo_status_notifications where document_id=doc.id) then return jsonb_build_object('skip',true,'combined_report',true);end if;$new$);
 definition:=replace(definition,$old$'status',b.status,'issue_detail',case when b.status='ISSUE_REPORTED' then$old$,$new$'status',coalesce(b.report_outcome,b.status),'issue_detail',case when coalesce(b.report_outcome,b.status)='ISSUE_REPORTED' then coalesce(nullif(b.report_detail,''),$new$);
 definition:=replace(definition,$old$order by e.id desc limit 1) else '' end,'reporter'$old$,$new$order by e.id desc limit 1)) else '' end,'reporter'$new$);
 execute definition;
end $migration$;
create function public.impjo_reset_report(p_actor uuid,p_action text,p_data jsonb) returns jsonb language plpgsql set search_path='' as $$
declare person public.impjo_principals;b public.impjo_bls;pending public.impjo_events;paths jsonb;files int;reports int;
begin
 select * into person from public.impjo_principals where id=p_actor and state='APPROVED' and archived_at is null for share;
 if not found or not exists(select 1 from public.impjo_roles where principal_id=p_actor and role='OPERATOR') then raise exception 'ACCESS_DENIED' using errcode='42501';end if;
 select bl.* into b from public.impjo_bls bl join public.impjo_jobs j on j.id=bl.job_id where bl.id=(p_data->>'bl_id')::uuid and j.archived_at is null for update of bl;
 if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
 if p_action='prepare' then
  if p_data->>'confirmed' is distinct from 'true' then raise exception 'DOCUMENT_CONFIRM_REQUIRED' using errcode='22023';end if;
  select * into pending from public.impjo_events where target_id=b.id and action='REPORT_RESET_FILES_PENDING' order by id desc limit 1 for update;
  if found then return jsonb_build_object('cleanup_id',pending.id,'paths',pending.detail::jsonb->'paths','file_count',pending.detail::jsonb->'file_count');end if;
  if p_data->>'expected_status' is distinct from b.status then raise exception 'STALE_STATUS' using errcode='22023';end if;
  perform 1 from public.impjo_status_notifications where bl_id=b.id for update;
  perform 1 from public.impjo_return_documents where bl_id=b.id for update;
  if exists(select 1 from public.impjo_status_notifications where bl_id=b.id and state='SENDING' and updated_at>now()-interval '15 minutes')
   or exists(select 1 from public.impjo_return_documents d left join public.impjo_document_deliveries x on x.document_id=d.id where d.bl_id=b.id and ((d.state='UPLOADING' and d.created_at>now()-interval '15 minutes') or (x.state='SENDING' and x.updated_at>now()-interval '15 minutes'))) then raise exception 'REPORT_RESET_BUSY' using errcode='22023';end if;
  select coalesce(jsonb_agg(object_path),'[]'),count(*) into paths,files from public.impjo_return_documents where bl_id=b.id;
  select count(*) into reports from public.impjo_status_notifications where bl_id=b.id;
  delete from public.impjo_status_notifications where bl_id=b.id;
  delete from public.impjo_return_documents where bl_id=b.id;
  delete from public.impjo_assignments where bl_id=b.id;
  delete from public.impjo_events where target_id=b.id and action<>'WORK_RESET';
  update public.impjo_bls set status='PENDING_HANDOVER',report_outcome=null,report_detail='' where id=b.id;
  insert into public.impjo_events(actor_id,action,target_id,detail) values(p_actor,'REPORT_RESET_FILES_PENDING',b.id,jsonb_build_object('paths',paths,'file_count',files,'report_count',reports)::text) returning * into pending;
  return jsonb_build_object('cleanup_id',pending.id,'paths',paths,'file_count',files);
 elsif p_action='finish' then
  select * into pending from public.impjo_events where id=(p_data->>'cleanup_id')::bigint and target_id=b.id and action='REPORT_RESET_FILES_PENDING' for update;
  if not found then raise exception 'NOT_FOUND' using errcode='P0002';end if;
  update public.impjo_events set action='WORK_RESET',detail=jsonb_build_object('files_deleted',(pending.detail::jsonb->>'file_count')::int,'reports_deleted',(pending.detail::jsonb->>'report_count')::int)::text where id=pending.id;
  return jsonb_build_object('reset',true,'files_deleted',true,'status',b.status);
 end if;
 raise exception 'UNKNOWN_ACTION' using errcode='22023';
end $$;
revoke all on function public.impjo_reset_report(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.impjo_reset_report(uuid,text,jsonb) to service_role;
