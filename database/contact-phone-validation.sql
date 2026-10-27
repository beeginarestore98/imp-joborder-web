-- Reject non-phone values in all contact directory saves, including unified form.
do $migration$
declare definition text;needle text:='elsif p_action=''save'' then';
begin
 definition:=pg_get_functiondef('public.impjo_catalog_api(uuid,text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected catalog function';end if;
 execute replace(definition,needle,needle||$guard$
  if k='CONTACT' and (ph !~ '^[+]?[0-9][0-9 ().#xX-]{5,29}$' or length(regexp_replace(ph,'[^0-9]','','g')) not between 6 and 20) then raise exception 'INVALID_CATALOG' using errcode='22023';end if;
$guard$);
end $migration$;
