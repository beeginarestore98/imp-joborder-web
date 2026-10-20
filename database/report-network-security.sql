-- pg_net ships broad network-table grants. Scheduler headers must stay backend-only.
revoke all on all tables in schema net from public,anon,authenticated;
revoke all on all sequences in schema net from public,anon,authenticated;
revoke all on all functions in schema net from public,anon,authenticated;
revoke all on schema net from public,anon,authenticated;
grant usage on schema net to postgres;
grant execute on all functions in schema net to postgres;
-- Rotate the dedicated credential after tightening extension defaults. No raw value leaves SQL/Vault.
do $$declare token text;secret_id uuid;begin
 token:=encode(extensions.gen_random_bytes(32),'hex');
 select id into secret_id from vault.secrets where name='impjo_evening_report_scheduler';
 if secret_id is null then raise exception 'REPORT_SCHEDULER_NOT_CONFIGURED';end if;
 perform vault.update_secret(secret_id,token);
 update public.impjo_report_settings set token_hash=encode(sha256(convert_to(token,'UTF8')),'hex') where id;
end $$;

