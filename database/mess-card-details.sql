-- Add existing B/L fields to authorized MESS browse; keep all role/date/page rules.
do $migration$
declare definition text;needle text:='select b.id,b.number,b.status,j.id as job_id';
begin
 definition:=pg_get_functiondef('public.impjo_mess_browse(uuid,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected MESS browse definition';end if;
 execute replace(definition,needle,'select b.id,b.number,b.status,b.destination,b.hbl,b.consignee,j.id as job_id');
end $migration$;
