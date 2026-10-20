-- Approved MESS share reporting rights; assignment is no longer needed for MESS.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=b.id and a.principal_id=p_actor and a.role=''MESS'' and a.revoked_at is null)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected MESS capability';end if;
 definition:=replace(definition,needle,'(v_person.kind=''LINE'' and ''MESS''=any(v_roles))');
 needle:='exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.bl_id=v_bl and a.principal_id=p_actor and a.role=''MESS'' and a.revoked_at is null)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected MESS status permission';end if;
 execute replace(definition,needle,'(v_person.kind=''LINE'' and ''MESS''=any(v_roles))');
 definition:=pg_get_functiondef('public.impjo_mess_browse(uuid,jsonb)'::regprocedure);
 needle:='exists(select 1 from public.impjo_assignments a where a.bl_id=b.id and a.principal_id=p_actor and a.role=''MESS'' and a.revoked_at is null)';
 if strpos(definition,needle)=0 then raise exception 'Unexpected MESS browse capability';end if;
 execute replace(definition,needle,'true');
end $migration$;

