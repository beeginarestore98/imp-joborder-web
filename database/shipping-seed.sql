-- Company names verified against BSAA Ordinary Members, retrieved 2026-10-20.
insert into public.impjo_catalog(kind,name,source_url)
select 'SHIPPING',name,'https://www.thaibsaa.com/index.php/members/members-directory/ordinary-members' from unnest(array[
'ALLIANCE SHIPPING SERVICES CO., LTD.','BANGKOK BARGE SERVICE CO., LTD.','BEN LINE AGENCIES (THAILAND) LTD.','CK LINE (THAILAND) CO., LTD.','CMA CGM (THAILAND) LTD.','COSCO SHIPPING LINES (THAILAND) CO., LTD.','COSIAM TRANSPORT CO., LTD.','CU LINES (THAILAND) CO., LTD.','ESL AGENCY (THAILAND) CO., LTD.','EVERGREEN SHIPPING AGENCY (THAILAND) CO., LTD.','FUJITRANS (THAILAND) CO., LTD.','GULF AGENCY COMPANY (THAILAND) LTD.','HAPAG-LLOYD (THAILAND) LTD.','HEUNG-A SHIPPING (THAILAND) CO., LTD.','HMM (THAILAND) CO., LTD.','INCHCAPE SHIPPING SERVICES (THAILAND) LTD.','INTERASIA LINES (THAILAND) CO., LTD.','JINJIANG SHIPPING AGENCY (THAILAND) CO., LTD.','K LINE (THAILAND) LTD.','KASE SHIPPING (THAILAND) CO., LTD.'
]) name on conflict do nothing;
insert into public.impjo_catalog(kind,name,source_url)
select 'SHIPPING',name,'https://www.thaibsaa.com/index.php/members/members-directory/ordinary-members?start=20' from unnest(array[
'KMTC (THAILAND) CO., LTD.','MAERSK LINE THAILAND LTD.','MEDITERRANEAN SHIPPING (THAILAND) CO., LTD.','MOL SHIPPING (THAILAND) CO., LTD.','NAM YUEN YONG SHIPPING CO., LTD.','NGOW HOCK AGENCY CO., LTD.','NYK LINE (THAILAND) CO., LTD.','OCEAN NETWORK EXPRESS (THAILAND) LTD.','OOCL (THAILAND) LTD.','PIL SHIPPING (THAILAND) LTD.','SAMUDERA TRAFFIC CO., LTD.'
]) name on conflict do nothing;

