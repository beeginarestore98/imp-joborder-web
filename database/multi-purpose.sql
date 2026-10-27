-- Multi-purpose job text uses newline-separated names in existing purpose column.
create or replace function impjo_private.job_amount(p_data jsonb) returns numeric language plpgsql stable set search_path='' as $$
declare value text:=nullif(btrim(p_data->>'amount'),'');required boolean;
begin
 select coalesce(bool_or(c.requires_amount),false) into required from public.impjo_catalog c where c.kind='PURPOSE' and exists(select 1 from regexp_split_to_table(coalesce(p_data->>'purpose',''),chr(10)) p(name) where lower(btrim(p.name))=lower(btrim(c.name)));
 if value is null then if required then raise exception 'AMOUNT_REQUIRED' using errcode='22023';end if;return null;end if;
 if value !~ '^[0-9]{1,10}([.][0-9]{1,2})?$' then raise exception 'INVALID_AMOUNT' using errcode='22023';end if;
 return value::numeric;
end $$;
do $migration$
declare definition text;needle text:='and kind=''CONTACT'' and archived_at is null for update;';
begin
 definition:=pg_get_functiondef('public.impjo_catalog_api(uuid,text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected catalog archive definition';end if;
 definition:=replace(definition,needle,'and kind in(''CONTACT'',''PURPOSE'') and archived_at is null for update;');
 definition:=replace(definition,'''CONTACT_ARCHIVED''','case when item.kind=''PURPOSE'' then ''PURPOSE_ARCHIVED'' else ''CONTACT_ARCHIVED'' end');
 definition:=replace(definition,'elsif p_action=''save'' then','elsif p_action=''save'' then'||chr(10)||' if k=''PURPOSE'' and (strpos(n,chr(10))>0 or strpos(n,chr(13))>0) then raise exception ''INVALID_CATALOG'' using errcode=''22023'';end if;');
 execute definition;
end $migration$;
