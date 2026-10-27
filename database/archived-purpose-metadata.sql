-- Retain metadata for purposes on an existing job without restoring archived choices.
do $migration$
declare definition text;needle text:='kind=k and archived_at is null and (';
begin
 definition:=pg_get_functiondef('public.impjo_catalog_api(uuid,text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected catalog list definition';end if;
 execute replace(definition,needle,$replacement$kind=k and (archived_at is null or (kind='PURPOSE' and name in(select jsonb_array_elements_text(case when jsonb_typeof(p_data->'retain_names')='array' then p_data->'retain_names' else '[]'::jsonb end)))) and ($replacement$);
end $migration$;
