import{gmailConfigured,type DocumentMail}from'./gmail-mailer.ts';
import{imagesToPdf,MAX_DOCUMENT_BYTES,MAX_DOCUMENT_PAGES}from'../shared/document-pdf.ts';
export type DocumentEnv={SUPABASE_URL:string;SUPABASE_SERVICE_ROLE_KEY:string;GMAIL_APP_PASSWORD?:string;DOCUMENT_FROM_EMAIL?:string;sendDocumentMail?:(mail:DocumentMail)=>Promise<{state:"ACCEPTED";providerId:string}>};
type RPC=(action:string,data:unknown)=>Promise<any>;
const BUCKET='impjo-return-documents';
const response=(data:unknown,status=200)=>Response.json(data,{status,headers:{'Cache-Control':'no-store'}});
function storageHeaders(env:DocumentEnv){const headers:Record<string,string>={apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY};return headers}
export function emailConfigured(env:DocumentEnv){return gmailConfigured(env)&&typeof env.sendDocumentMail==='function'}
export async function documentBody(request:Request){if(!request.headers.get('content-type')?.startsWith('application/json'))throw Error('JSON_REQUIRED');const reader=request.body?.getReader();if(!reader)throw Error('INVALID_DOCUMENT');const chunks:Uint8Array[]=[];let size=0;while(true){const{value,done}=await reader.read();if(done)break;size+=value.length;if(size>8*1024*1024){await reader.cancel();throw Error('DOCUMENT_LIMIT')}chunks.push(value)}const data=new Uint8Array(size);let offset=0;for(const c of chunks){data.set(c,offset);offset+=c.length}try{return JSON.parse(new TextDecoder().decode(data))}catch{throw Error('INVALID_DOCUMENT')}}
function base64(data:Uint8Array){let s='';for(let i=0;i<data.length;i+=16384)s+=String.fromCharCode(...data.subarray(i,i+16384));return btoa(s)}
async function storedFile(env:DocumentEnv,path:string){const r=await fetch(env.SUPABASE_URL+'/storage/v1/object/authenticated/'+BUCKET+'/'+path,{headers:storageHeaders(env),signal:AbortSignal.timeout(12000)});if(!r.ok)throw Error('DOCUMENT_STORAGE_FAILED');return new Uint8Array(await r.arrayBuffer())}
export async function documentRequest(request:Request,path:string,env:DocumentEnv,call:RPC){
 const ready=emailConfigured(env),url=new URL(request.url);
 try{
  if(request.method==='GET'){
   if(path==='documents/recipients')return response({...await call('recipients',{}),integration_ready:ready});
   if(path==='documents/context')return response({...await call('context',{bl_id:url.searchParams.get('bl_id')}),integration_ready:ready});
   const match=path.match(/^documents\/([0-9a-f-]{36})\/file$/);
   if(match){const d=await call('file',{id:match[1]});const file=await storedFile(env,d.path);return new Response(file,{headers:{'Content-Type':'application/pdf','Content-Disposition':'inline; filename="IMP-return-document.pdf"','Cache-Control':'private, no-store','X-Content-Type-Options':'nosniff','Content-Security-Policy':"sandbox; default-src 'none'"}})}
  }
  if(request.method!=='POST')return response({error:'NOT_FOUND'},404);
  const data=await documentBody(request);
  if(path==='documents/recipients')return response(await call('recipient_save',data));
  if(path==='documents/upload'){
   if(!/^[0-9a-f-]{36}$/.test(data.id||'')||!Array.isArray(data.pages)||data.pages.length<1||data.pages.length>MAX_DOCUMENT_PAGES)throw Error('INVALID_DOCUMENT');
   const pages:Uint8Array[]=data.pages.map((p:unknown)=>{if(typeof p!=='string'||p.length>MAX_DOCUMENT_BYTES*1.4||!/^[A-Za-z0-9+/]+={0,2}$/.test(p))throw Error('INVALID_DOCUMENT_IMAGE');return Uint8Array.from(atob(p),c=>c.charCodeAt(0))});
   const pdf=imagesToPdf(pages),hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',pdf))).map(n=>n.toString(16).padStart(2,'0')).join('');
   const d=await call('reserve',{id:data.id,bl_id:data.bl_id,sha256:hash,pages:pages.length,bytes:pdf.length});
   if(d.state==='UPLOADING'){
    const result=await fetch(env.SUPABASE_URL+'/storage/v1/object/'+BUCKET+'/'+d.path,{method:'POST',headers:{...storageHeaders(env),'Content-Type':'application/pdf','x-upsert':'false'},body:pdf,signal:AbortSignal.timeout(12000)});
    if(!result.ok){const existing=await storedFile(env,d.path);const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',existing))).map(n=>n.toString(16).padStart(2,'0')).join('');if(digest!==hash)throw Error('DOCUMENT_STORAGE_FAILED')}
    try{await call('complete',{id:data.id})}catch(error){
     // A job/account can be revoked after upload; do not leave its newly uploaded PDF accessible.
     try{await fetch(env.SUPABASE_URL+'/storage/v1/object/'+BUCKET,{method:'DELETE',headers:{...storageHeaders(env),'Content-Type':'application/json'},body:JSON.stringify({prefixes:[d.path]}),signal:AbortSignal.timeout(8000)})}catch{/* The bucket remains private even when cleanup is unavailable. */}
     throw error;
    }
   }return response({id:data.id,state:'READY'});
  }
  if(path==='documents/send'){
   if(!ready)return response({error:'EMAIL_NOT_CONFIGURED'},503);
   if(data.confirmed!==true)throw Error('DOCUMENT_CONFIRM_REQUIRED');
   await call('submit',{id:data.id,recipient_version:data.recipient_version});
   await Promise.all(['email'].map(async channel=>{
    const claim=await call('claim',{id:data.id,channel});if(claim.skip)return;
    let state='UNKNOWN',provider_id='',error='DELIVERY_UNCONFIRMED';
    try{
     const pdf=await storedFile(env,claim.path);const key=data.id+':'+channel;
     const result=await env.sendDocumentMail!({to:claim.recipient,jobNumber:claim.job_number,blNumber:claim.bl_number,contact:claim.contact,documentId:data.id,pdfBase64:base64(pdf)});
     provider_id=result.providerId;state=result.state;error='';
// Any network/ambiguous reply stays UNKNOWN; never blindly resend a potentially delivered file.
    }catch(e){if((e as Error).message==='EMAIL_PROVIDER_REJECTED'){state='FAILED';error='EMAIL_PROVIDER_REJECTED'}/* Unknown delivery must not be automatically retried. */}
    await call('finish',{id:data.id,channel,lease:claim.lease,state,provider_id,error});
   }));return response({id:data.id,submitted:true});
  }
  return response({error:'NOT_FOUND'},404);
 }catch(e){const code=(e as Error).message;const safe=['INVALID_DOCUMENT','INVALID_DOCUMENT_IMAGE','DOCUMENT_LIMIT','DOCUMENT_STORAGE_FAILED','DOCUMENT_CONFIRM_REQUIRED','JSON_REQUIRED'];if(safe.includes(code))return response({error:code},400);throw e}
}

// Called only after the existing authorized permanent Job deletion succeeds.
export async function cleanupDocumentFiles(env:DocumentEnv,jobId:string){
 if(!/^[0-9a-f-]{36}$/.test(jobId))throw Error('INVALID_DOCUMENT');
 for(let batch=0;batch<20;batch++){
  const r=await fetch(env.SUPABASE_URL+'/storage/v1/object/list/'+BUCKET,{method:'POST',headers:{...storageHeaders(env),'Content-Type':'application/json'},body:JSON.stringify({prefix:jobId+'/',limit:100,offset:0}),signal:AbortSignal.timeout(10000)});
  if(!r.ok)throw Error('DOCUMENT_STORAGE_FAILED');const files=await r.json() as {name:string;id:string|null}[];if(!files.length)return;
  const prefixes=files.filter(f=>f.id&&/^[0-9a-f-]{36}\.pdf$/.test(f.name)).map(f=>jobId+'/'+f.name);if(prefixes.length!==files.length)throw Error('DOCUMENT_STORAGE_FAILED');
  const removed=await fetch(env.SUPABASE_URL+'/storage/v1/object/'+BUCKET,{method:'DELETE',headers:{...storageHeaders(env),'Content-Type':'application/json'},body:JSON.stringify({prefixes}),signal:AbortSignal.timeout(10000)});if(!removed.ok)throw Error('DOCUMENT_STORAGE_FAILED');
 }throw Error('DOCUMENT_STORAGE_FAILED');
}
