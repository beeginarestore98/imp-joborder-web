begin;
do $$
declare nonce uuid:=gen_random_uuid();epoch bigint:=extract(epoch from now())::bigint;token text;signature text;denied boolean;
begin
 select decrypted_secret into token from vault.decrypted_secrets where name='impjo_evening_report_scheduler';
 signature:=encode(extensions.hmac(convert_to(nonce::text||'.'||epoch::text,'UTF8'),convert_to(token,'UTF8'),'sha256'),'hex');
 update public.impjo_report_settings set enabled=false where id;
 assert public.impjo_report_claim_signed(nonce,epoch,signature)='[]'::jsonb,'Valid proof rejected';
 denied:=false;begin perform public.impjo_report_claim_signed(nonce,epoch,signature);exception when invalid_authorization_specification then denied:=true;end;assert denied,'Scheduler proof replay accepted';
 denied:=false;begin perform public.impjo_report_claim_signed(gen_random_uuid(),epoch-300,signature);exception when invalid_authorization_specification then denied:=true;end;assert denied,'Expired scheduler proof accepted';
 denied:=false;begin perform public.impjo_report_claim_signed(gen_random_uuid(),epoch,repeat('0',64));exception when invalid_authorization_specification then denied:=true;end;assert denied,'Forged scheduler signature accepted';
 assert not has_function_privilege('anon','public.impjo_report_claim_signed(uuid,bigint,text)','EXECUTE'),'Client scheduler RPC access';
 assert not has_table_privilege('authenticated','vault.decrypted_secrets','SELECT'),'Client Vault access';
end $$;
rollback;
select 'PASS: scheduler HMAC proof, single-use nonce, expiry, forged signature denial and Vault isolation. No reports sent.' as result;

