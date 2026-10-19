type Env={IMPJO_GATEWAY_SECRET:string};
export async function onRequest({request,env}:{request:Request;env:Env}){
 if(!env.IMPJO_GATEWAY_SECRET)return Response.json({error:'SETUP_REQUIRED'},{status:503,headers:{'Cache-Control':'no-store'}});
 const original=new URL(request.url);const upstream=new URL('https://pqnqgwkivoiikyisydul.supabase.co/functions/v1/impjo-api'+original.pathname);upstream.search=original.search;
 const headers=new Headers({'X-IMP-Gateway':env.IMPJO_GATEWAY_SECRET});
 for(const name of ['content-type','cookie','origin','x-imp-client','x-line-signature']){const value=request.headers.get(name);if(value)headers.set(name,value)}
 try{const response=await fetch(upstream,{method:request.method,headers,body:['GET','HEAD'].includes(request.method)?undefined:request.body,redirect:'manual',signal:AbortSignal.timeout(30000)});const returned=new Headers(response.headers);returned.set('Cache-Control','no-store');returned.set('X-Content-Type-Options','nosniff');return new Response(response.body,{status:response.status,headers:returned})}catch{return Response.json({error:'SERVICE_UNAVAILABLE'},{status:503,headers:{'Cache-Control':'no-store'}})}
}
