-- Approved OUTSOURCE may read all jobs; write/assignment rules stay separate.
create or replace function public.impjo_visible_bl(p_actor uuid,p_bl uuid)
returns boolean language sql stable set search_path='' as $function$
 select exists(select 1 from public.impjo_principals p where p.id=p_actor and p.state='APPROVED') and (
 exists(select 1 from public.impjo_roles where principal_id=p_actor and role in ('ADMIN','OPERATOR','OUTSOURCE')) or
 exists(select 1 from public.impjo_assignments a join public.impjo_roles r on r.principal_id=a.principal_id and r.role=a.role where a.principal_id=p_actor and a.bl_id=p_bl and a.revoked_at is null))
$function$;
revoke all on function public.impjo_visible_bl(uuid,uuid) from public,anon,authenticated;
grant execute on function public.impjo_visible_bl(uuid,uuid) to service_role;
