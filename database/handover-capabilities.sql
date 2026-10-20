-- Read-all does not imply write-all: advertise the same server authorization in UI.
do $migration$
declare definition text; needle text; replacement text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='jsonb_agg(to_jsonb(b) order by b.number)';
 replacement:=$new$jsonb_agg(to_jsonb(b)||jsonb_build_object('can_handover',b.status='PENDING_HANDOVER' and ((v_person.kind='STAFF' and 'OPERATOR'=any(v_roles)) or exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=b.id and a.principal_id=p_actor and a.role='OUTSOURCE' and a.revoked_at is null))) order by b.number)$new$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected live BL projection'; end if;
 execute replace(definition,needle,replacement);
end;
$migration$;
