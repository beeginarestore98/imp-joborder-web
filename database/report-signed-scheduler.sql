-- Managed pg_net objects retain owner grants. Never place a reusable credential in their queue.
-- Send a short-lived, one-use HMAC proof; the Vault key stays inside Postgres.
create table public.impjo_report_requests(nonce uuid primary key,created_at timestamptz not null default now());
alter table public.impjo_report_requests enable row level security;
revoke all on public.impjo_report_requests from public,anon,authenticated;
grant all on public.impjo_report_requests to service_role;
create function impjo_private.verify_report_proof(p_nonce uuid,p_timestamp bigint,p_signature text) returns boolean language plpgsql security definer set search_path='' as $$
declare token text;expected text;epoch bigint;
begin
 epoch:=extract(epoch from now())::bigint;
 if p_nonce is null or p_timestamp is null or p_timestamp<epoch-120 or p_timestamp>epoch+30 or coalesce(p_signature,'') !~ '^[0-9a-f]{64}$' then return false;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='impjo_evening_report_scheduler';
 expected:=encode(extensions.hmac(convert_to(p_nonce::text||'.'||p_timestamp::text,'UTF8'),convert_to(token,'UTF8'),'sha256'),'hex');
 if expected is null or p_signature<>expected then return false;end if;
 insert into public.impjo_report_requests(nonce) values(p_nonce) on conflict do nothing;
 if not found then return false;end if;
 delete from public.impjo_report_requests where created_at<now()-interval '1 day';
 return true;
end $$;
revoke all on function impjo_private.verify_report_proof(uuid,bigint,text) from public,anon,authenticated;
grant execute on function impjo_private.verify_report_proof(uuid,bigint,text) to service_role;
create function public.impjo_report_claim_signed(p_nonce uuid,p_timestamp bigint,p_signature text) returns jsonb language plpgsql set search_path='' as $$
begin
 if not impjo_private.verify_report_proof(p_nonce,p_timestamp,p_signature) then raise exception 'AUTH_REQUIRED' using errcode='28000';end if;
 return public.impjo_report_claim((select token_hash from public.impjo_report_settings where id));
end $$;
revoke all on function public.impjo_report_claim_signed(uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.impjo_report_claim_signed(uuid,bigint,text) to service_role;
create or replace function impjo_private.kick_report_delivery() returns bigint language plpgsql set search_path='' as $$
declare token text;request_id bigint;nonce uuid:=gen_random_uuid();epoch bigint:=extract(epoch from now())::bigint;signature text;
begin
 if not exists(select 1 from public.impjo_report_settings where id and enabled) or not exists(select 1 from public.impjo_report_outbox where attempts<5 and next_attempt_at<=now() and created_at>now()-interval '23 hours' and (state in ('QUEUED','FAILED') or(state='SENDING' and locked_until<now()))) then return null;end if;
 select decrypted_secret into token from vault.decrypted_secrets where name='impjo_evening_report_scheduler';
 if token is null then raise exception 'REPORT_SCHEDULER_NOT_CONFIGURED';end if;
 signature:=encode(extensions.hmac(convert_to(nonce::text||'.'||epoch::text,'UTF8'),convert_to(token,'UTF8'),'sha256'),'hex');
 select net.http_post(url:='https://pqnqgwkivoiikyisydul.supabase.co/functions/v1/impjo-reports',headers:=jsonb_build_object('Content-Type','application/json','x-imp-report-nonce',nonce::text,'x-imp-report-time',epoch::text,'x-imp-report-signature',signature),body:='{}'::jsonb,timeout_milliseconds:=60000) into request_id;
 return request_id;
end $$;
revoke all on function impjo_private.kick_report_delivery() from public,anon,authenticated,service_role;

