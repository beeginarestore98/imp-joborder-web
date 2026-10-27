-- Approved extension: user-managed B/L dropdowns, separate from old shipping seeds.
alter table public.impjo_catalog drop constraint impjo_catalog_kind_check;
alter table public.impjo_catalog add constraint impjo_catalog_kind_check check(kind in('CONTACT','PURPOSE','SHIPPING','DESTINATION','CONSIGNEE'));
do $migration$
declare definition text;
begin
 definition:=pg_get_functiondef('public.impjo_catalog_api(uuid,text,jsonb)'::regprocedure);
 if strpos(definition,'k not in(''CONTACT'',''PURPOSE'',''SHIPPING'')')=0 then raise exception 'Unexpected catalog list validation';end if;
 definition:=replace(definition,'k not in(''CONTACT'',''PURPOSE'',''SHIPPING'')','k not in(''CONTACT'',''PURPOSE'',''SHIPPING'',''DESTINATION'',''CONSIGNEE'')');
 definition:=replace(definition,'k not in(''CONTACT'',''PURPOSE'')','k not in(''CONTACT'',''PURPOSE'',''DESTINATION'',''CONSIGNEE'')');
 definition:=replace(definition,'and kind in(''CONTACT'',''PURPOSE'') and archived_at is null for update;','and kind in(''CONTACT'',''PURPOSE'',''DESTINATION'',''CONSIGNEE'') and archived_at is null for update;');
 definition:=replace(definition,$old$case when item.kind='PURPOSE' then 'PURPOSE_ARCHIVED' else 'CONTACT_ARCHIVED' end$old$,$new$item.kind||'_ARCHIVED'$new$);
 execute definition;
end $migration$;
