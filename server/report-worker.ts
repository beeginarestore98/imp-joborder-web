import{formatEveningReport,type EveningPayload}from'./report-format.ts';
type Env={SUPABASE_URL:string;SUPABASE_SERVICE_ROLE_KEY:string;LINE_MESSAGING_CHANNEL_ACCESS_TOKEN:string};
type Delivery={id:string;lease:string;payload:EveningPayload};
export async function onReportRequest(request:Request,env:Env){
 const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
 if(request.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.LINE_MESSAGING_CHANNEL_ACCESS_TOKEN)return reply({error:'NOT_CONFIGURED'},503);
 const nonce=request.headers.get('x-imp-report-nonce')||'',timestamp=request.headers.get('x-imp-report-time')||'',signature=request.headers.get('x-imp-report-signature')||'';
 if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(nonce)||!/^\d{10}$/.test(timestamp)||!/^[0-9a-f]{64}$/.test(signature))return reply({error:'UNAUTHORIZED'},401);
 async function rpc(name:string,data:unknown){
  const headers:Record<string,string>={apikey:env.SUPABASE_SERVICE_ROLE_KEY,'Content-Type':'application/json'};
  if(env.SUPABASE_SERVICE_ROLE_KEY.startsWith('eyJ'))headers.Authorization='Bearer '+env.SUPABASE_SERVICE_ROLE_KEY;
  const res=await fetch(env.SUPABASE_URL+'/rest/v1/rpc/'+name,{method:'POST',headers,body:JSON.stringify(data),signal:AbortSignal.timeout(15000)});
  if(!res.ok)throw Error(res.status===401||res.status===403?'UNAUTHORIZED':'RPC_FAILED');
  const text=await res.text();return text?JSON.parse(text):null;
 }
 let deliveries:Delivery[];
 try{deliveries=await rpc('impjo_report_claim_signed',{p_nonce:nonce,p_timestamp:Number(timestamp),p_signature:signature})}catch(error){return reply({error:(error as Error).message},(error as Error).message==='UNAUTHORIZED'?401:503)}
 let accepted=0,failed=0;
 async function send(item:Delivery){
  let ok=false,retry=false,error='';
  try{
   const destination=await rpc('impjo_report_destination',{p_id:item.id,p_lease:item.lease});
   if(!/^U[0-9a-f]{32}$/.test(destination||''))throw Error('RECIPIENT_REVOKED');
   const text=formatEveningReport(item.payload);if(text.length>5000)throw Error('REPORT_TOO_LONG');
   const res=await fetch('https://api.line.me/v2/bot/message/push',{method:'POST',headers:{Authorization:'Bearer '+env.LINE_MESSAGING_CHANNEL_ACCESS_TOKEN,'Content-Type':'application/json','X-Line-Retry-Key':item.id},body:JSON.stringify({to:destination,messages:[{type:'text',text}]}),signal:AbortSignal.timeout(10000)});
   ok=res.ok||(res.status===409&&!!res.headers.get('x-line-accepted-request-id'));
   if(!ok){error='LINE_HTTP_'+res.status;retry=res.status>=500||res.status===429;}
  }catch(e){error=(e as Error).message==='RECIPIENT_REVOKED'?'RECIPIENT_REVOKED':(e as Error).message==='REPORT_TOO_LONG'?'REPORT_TOO_LONG':'DELIVERY_NETWORK_ERROR';retry=error==='DELIVERY_NETWORK_ERROR';}
  try{await rpc('impjo_report_finish',{p_id:item.id,p_lease:item.lease,p_ok:ok,p_error:error,p_retry:retry});if(ok)accepted++;else failed++;}catch{failed++;}
 }
 // Bounded concurrency keeps an evening batch within the scheduler request timeout.
 for(let i=0;i<deliveries.length;i+=5)await Promise.all(deliveries.slice(i,i+5).map(send));
 return reply({processed:deliveries.length,accepted,failed});
}

