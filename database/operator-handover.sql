-- Extend only the existing pending -> in progress transition.
-- Approved staff OPERATOR can hand over; assigned OUTSOURCE retains access.
do $migration$
declare definition text; old_condition text; new_condition text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 old_condition:=$old$v_old='PENDING_HANDOVER' and v_new='IN_PROGRESS' and exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null)$old$;
 new_condition:=$new$v_old='PENDING_HANDOVER' and v_new='IN_PROGRESS' and ((v_person.kind='STAFF' and 'OPERATOR'=any(v_roles)) or exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null))$new$;
 if strpos(definition,old_condition)=0 then raise exception 'Unexpected live handover rule; review before applying'; end if;
 execute replace(definition,old_condition,new_condition);
end;
$migration$;