-- ADMIN may approve an existing verified LINE principal as OPERATOR for handover.
-- This is independent of linking to staff email and never creates a staff identity.
do $migration$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.impjo_api(uuid,text,jsonb)'::regprocedure);
 needle:='(kind=''LINE'' and v_role in (''OUTSOURCE'',''MESS''))';
 if strpos(definition,needle)=0 then raise exception 'Unexpected approval rule';end if;
 definition:=replace(definition,needle,'(kind=''LINE'' and v_role in (''OUTSOURCE'',''MESS'',''OPERATOR''))');
 needle:='(v_person.kind=''STAFF'' and ''OPERATOR''=any(v_roles))';
 if strpos(definition,needle)=0 then raise exception 'Unexpected handover rule';end if;
 execute replace(definition,needle,'(v_person.kind in (''STAFF'',''LINE'') and ''OPERATOR''=any(v_roles))');
 definition:=pg_get_functiondef('public.impjo_handover_list(uuid,integer,text)'::regprocedure);
 needle:='p.kind=''STAFF'' and r.role=''OPERATOR''';
 if strpos(definition,needle)=0 then raise exception 'Unexpected handover list rule';end if;
 definition:=replace(definition,needle,'p.kind in (''STAFF'',''LINE'') and r.role=''OPERATOR''');
 execute replace(definition,'id=p_actor and state=''APPROVED''','id=p_actor and state=''APPROVED'' and archived_at is null');
end $migration$;

create function public.impjo_operator_actor(p_subject text) returns uuid language plpgsql stable set search_path='' as $$
declare actor uuid;
begin
 actor:=public.impjo_line_actor(p_subject);
 if exists(select 1 from public.impjo_principals p join public.impjo_roles r on r.principal_id=p.id where p.id=actor and p.kind='LINE' and p.state='APPROVED' and p.archived_at is null and r.role='OPERATOR') then return actor;end if;
 return public.impjo_chat_staff_actor(p_subject);
end $$;
revoke all on function public.impjo_operator_actor(text) from public,anon,authenticated;
grant execute on function public.impjo_operator_actor(text) to service_role;

