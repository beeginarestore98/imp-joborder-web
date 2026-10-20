-- OPERATOR and assigned OUTSOURCE may reopen completed work; MESS retains assigned reporting.
do $migration$
declare definition text; start_at int; end_at int; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 start_at:=strpos(definition,'  if not ((v_old=''PENDING_HANDOVER''');
 end_at:=strpos(definition,'  if v_new=''ISSUE_REPORTED''');
 if start_at=0 or end_at<=start_at then raise exception 'Unexpected status permission rule';end if;
 definition:=overlay(definition placing $rule$
  if v_new is null or v_new not in ('PENDING_HANDOVER','IN_PROGRESS','ISSUE_REPORTED','COMPLETED') then raise exception 'INVALID_STATUS_TRANSITION' using errcode='22023';end if;
  if not ((v_person.kind in ('STAFF','LINE') and 'OPERATOR'=any(v_roles))
   or exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null)
   or (v_old='IN_PROGRESS' and v_new in ('COMPLETED','ISSUE_REPORTED') and exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='MESS' and a.revoked_at is null))) then raise exception 'INVALID_STATUS_TRANSITION' using errcode='42501';end if;
  if p_data ? 'expected_status' and p_data->>'expected_status' is distinct from v_old then raise exception 'STALE_STATUS' using errcode='22023';end if;
  if v_new=v_old then return jsonb_build_object('ok',true,'unchanged',true);end if;
$rule$ from start_at for end_at-start_at);
 needle:='jsonb_build_object(''can_report'',';
 if strpos(definition,needle)=0 then raise exception 'Unexpected detail capabilities';end if;
 execute replace(definition,needle,'jsonb_build_object(''can_update'',((v_person.kind in (''STAFF'',''LINE'') and ''OPERATOR''=any(v_roles)) or exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=b.id and a.principal_id=p_actor and a.role=''OUTSOURCE'' and a.revoked_at is null)),''can_report'',');
 definition:=pg_get_functiondef('public.impjo_handover_list(uuid,integer,text)'::regprocedure);
 needle:='j.archived_at is null and b.status=''PENDING_HANDOVER'' and';
 if strpos(definition,needle)=0 then raise exception 'Unexpected chat list filter';end if;
 execute replace(definition,needle,'j.archived_at is null and');
end $migration$;

