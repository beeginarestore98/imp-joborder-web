import nodemailer from 'npm:nodemailer@10.2.1';
import{sendGmailDocument,type TransportFactory}from'./gmail-mailer.ts';
import{onRequest}from'./backend.ts';
declare const Deno:{env:{get:(key:string)=>string|undefined};serve:(handler:(req:Request)=>Promise<Response>)=>void};
async function same(a:string,b:string){const enc=new TextEncoder();const [x,y]=await Promise.all([crypto.subtle.digest('SHA-256',enc.encode(a)),crypto.subtle.digest('SHA-256',enc.encode(b))]);const aa=new Uint8Array(x),bb=new Uint8Array(y);let diff=0;for(let i=0;i<aa.length;i++)diff|=aa[i]^bb[i];return diff===0}
Deno.serve(async request=>{
 const gateway=Deno.env.get('IMPJO_GATEWAY_SECRET');if(!gateway||!await same(request.headers.get('x-imp-gateway')||'',gateway))return Response.json({error:'UNAUTHORIZED_GATEWAY'},{status:401,headers:{'Cache-Control':'no-store'}});
 const input=new URL(request.url);const at=input.pathname.indexOf('/api/');if(at<0)return new Response(null,{status:404});
 const target=new URL('https://imp-joborder-web.pages.dev'+input.pathname.slice(at));target.search=input.search;
 const env={GMAIL_APP_PASSWORD:Deno.env.get('GMAIL_APP_PASSWORD')||'',DOCUMENT_FROM_EMAIL:Deno.env.get('DOCUMENT_FROM_EMAIL')||'',SUPABASE_URL:Deno.env.get('SUPABASE_URL')||'',SUPABASE_SERVICE_ROLE_KEY:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||'',SUPABASE_PUBLISHABLE_KEY:Deno.env.get('SUPABASE_ANON_KEY')||'',LINE_LOGIN_CHANNEL_ID:'2012071986',LINE_LOGIN_CHANNEL_SECRET:Deno.env.get('LINE_LOGIN_CHANNEL_SECRET')||'',LIFF_ID:'2012071986-ymuhMXOT',LINE_MESSAGING_CHANNEL_SECRET:Deno.env.get('LINE_MESSAGING_CHANNEL_SECRET')||'',LINE_MESSAGING_CHANNEL_ACCESS_TOKEN:Deno.env.get('LINE_MESSAGING_CHANNEL_ACCESS_TOKEN')||''};
 const sendDocumentMail=(mail:import('./gmail-mailer.ts').DocumentMail)=>sendGmailDocument(env,mail,nodemailer.createTransport as TransportFactory);
 return onRequest({request:new Request(target,request),env:{...env,sendDocumentMail},params:{}});
});
