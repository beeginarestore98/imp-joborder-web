-- pg_net was introduced by this feature and has only two QA HTTP responses.
-- It is non-relocatable. Reinstall without CASCADE while reports remain OFF.
begin;
do $$ begin
 if exists(select 1 from public.impjo_report_settings where enabled) or exists(select 1 from public.impjo_report_outbox) then raise exception 'Reports must be inactive and empty before network extension setup';end if;
end $$;
drop extension pg_net;
create extension pg_net with schema extensions;
commit;

