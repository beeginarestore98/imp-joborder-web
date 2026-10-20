-- Owner-approved rule: no per-job assignee is required for approved OUTSOURCE.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=b.id and a.principal_id=p_actor and a.role=''OUTSOURCE'' and a.revoked_at is null)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected OUTSOURCE capability';end if;
 definition:=replace(definition,needle,'(v_person.kind=''LINE'' and ''OUTSOURCE''=any(v_roles))');
 needle:='exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role=''OUTSOURCE'' and a.revoked_at is null)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected OUTSOURCE status rule';end if;
 execute replace(definition,needle,'(v_person.kind=''LINE'' and ''OUTSOURCE''=any(v_roles))');
 definition:=pg_get_functiondef('public.impjo_handover_list(uuid,integer,text)'::regprocedure);
 needle:='(staff or exists(select 1 from public.impjo_assignments a where a.bl_id=b.id and a.principal_id=p_actor and a.role=''OUTSOURCE'' and a.revoked_at is null))';
 if strpos(definition,needle)=0 then raise exception 'Unexpected OUTSOURCE list rule';end if;
 execute replace(definition,needle,'(staff or outsourced)');
end $migration$;

