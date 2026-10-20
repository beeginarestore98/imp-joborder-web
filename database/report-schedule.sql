create extension if not exists pg_cron;
create extension if not exists pg_net;
create function impjo_private.kick_report_delivery() returns bigint language plpgsql set search_path='' as $$
declare token text;request_id bigint;
begin
 if not exists(select 1 from public.impjo_report_settings where id and enabled) or not exists(select 1 from public.impjo_report_outbox where attempts<5 and next_attempt_at<=now() and created_at>now()-interval '23 hours' and (state in ('QUEUED','FAILED') or(state='SENDING' and locked_until<now()))) then return null;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='impjo_evening_report_scheduler';
 if token is null then raise exception 'REPORT_SCHEDULER_NOT_CONFIGURED';end if;
 select net.http_post(url:='https://pqnqgwkivoiikyisydul.supabase.co/functions/v1/impjo-reports',headers:=jsonb_build_object('Content-Type','application/json','x-imp-report-scheduler',token),body:='{}'::jsonb,timeout_milliseconds:=60000) into request_id;
 return request_id;
end $$;
revoke all on function impjo_private.kick_report_delivery() from public,anon,authenticated,service_role;
-- pg_cron uses UTC. 10:00 UTC = 17:00 Asia/Bangkok, with no DST.
select cron.schedule('impjo-evening-report-1700','0 10 * * *',$cron$select impjo_private.enqueue_evening_reports();$cron$);
select cron.schedule('impjo-report-delivery','* * * * *',$cron$select impjo_private.kick_report_delivery();$cron$);
