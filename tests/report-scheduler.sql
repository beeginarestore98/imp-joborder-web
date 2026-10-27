begin;
do $$begin
 assert not exists(select 1 from cron.job where active and jobname like '%impjo%report%'),'Removed report scheduler is active';
end $$;
rollback;
