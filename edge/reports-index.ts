import{onReportRequest}from'./report-worker.ts';
declare const Deno:{env:{get:(key:string)=>string|undefined};serve:(handler:(req:Request)=>Promise<Response>)=>void};
Deno.serve(request=>onReportRequest(request,{SUPABASE_URL:Deno.env.get('SUPABASE_URL')||'',SUPABASE_SERVICE_ROLE_KEY:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'',LINE_MESSAGING_CHANNEL_ACCESS_TOKEN:Deno.env.get('LINE_MESSAGING_CHANNEL_ACCESS_TOKEN')||''}));
