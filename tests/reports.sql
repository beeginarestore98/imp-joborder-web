begin;
do $$declare denied boolean;begin
 denied:=false;begin perform public.impjo_reports(null,'recipient','{}');exception when feature_not_supported then denied:=sqlerrm='FEATURE_REMOVED';end;
 assert denied,'Removed daily reports became available';
end $$;
rollback;
