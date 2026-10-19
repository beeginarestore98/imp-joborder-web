type Env={SUPABASE_URL:string;SUPABASE_SERVICE_ROLE_KEY:string;SUPABASE_PUBLISHABLE_KEY:string;LINE_LOGIN_CHANNEL_ID:string;LINE_LOGIN_CHANNEL_SECRET:string;LIFF_ID:string;LINE_MESSAGING_CHANNEL_SECRET:string;LINE_MESSAGING_CHANNEL_ACCESS_TOKEN:string};
type Ctx={request:Request;env:Env;params:Record<string,string|string[]>};
const ORIGIN='https://imp-joborder-web.pages.dev';
const cookie=(name:string,value:string,age:number)=>`__Host-impjo_${name}=${encodeURIComponent(value)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${age}`;
const json=(body:unknown,status=200,cookies:string[]=[])=>{const headers=new Headers({'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});for(const c of cookies)headers.append('Set-Cookie',c);return new Response(JSON.stringify(body),{status,headers})};
class ApiError extends Error{status:number;constructor(message:string,status=400){super(message);this.status=status}}
const getCookie=(r:Request,n:string)=>{const p=(r.headers.get('cookie')||'').split(';').map(v=>v.trim()).find(v=>v.startsWith(`__Host-impjo_${n}=`));try{return p?decodeURIComponent(p.slice(p.indexOf('=')+1)):''}catch{return ''}};
export async function digest(value:string){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(v=>v.toString(16).padStart(2,'0')).join('')}
async function sb(env:Env,path:string,body?:unknown,auth?:string,method?:string){
 const key=auth?env.SUPABASE_PUBLISHABLE_KEY:env.SUPABASE_SERVICE_ROLE_KEY;
 const headers:Record<string,string>={apikey:key,'Content-Type':'application/json'};if(path.startsWith('/rest/')&&body!==undefined)headers.Prefer='return=representation';if(auth&&!auth.startsWith('sb_publishable_'))headers.Authorization=`Bearer ${auth}`;
 else if(key?.startsWith('eyJ'))headers.Authorization=`Bearer ${key}`;
 const response=await fetch(`${env.SUPABASE_URL}${path}`,{method:method||(body===undefined?'GET':'POST'),headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 const raw=await response.text();const data=(raw?JSON.parse(raw):{}) as Record<string,unknown>;
 if(!response.ok){const code=String(data.code||'');const known=['AUTH_REQUIRED','APPROVAL_REQUIRED','ACCESS_DENIED','NOT_FOUND','INVALID_BL_LIST','INVALID_ROLE','CANNOT_CHANGE_SELF','INVALID_IDENTITY_ROLE','ASSIGNEE_NOT_APPROVED','INVALID_STATUS_TRANSITION','ISSUE_DETAIL_REQUIRED','DETAIL_TOO_LONG'];const msg=String(data.message||'');throw new ApiError(known.includes(msg)?msg:code==='23505'?'DUPLICATE_RECORD':path.startsWith('/auth/')?'AUTH_FAILED':'DATABASE_REQUEST_FAILED',path.startsWith('/auth/')||code==='28000'?401:code==='42501'?403:code==='P0002'?404:400)}
 return data;
}
const rpc=(env:Env,name:string,data:unknown)=>sb(env,`/rest/v1/rpc/${name}`,data);
const random=()=>Array.from(crypto.getRandomValues(new Uint8Array(32))).map(v=>v.toString(16).padStart(2,'0')).join('');
function sessionId(token:string){try{const payload=JSON.parse(atob(token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/')));if(typeof payload.session_id==='string')return payload.session_id}catch{/* Token validity is checked by Supabase Auth first. */}throw new ApiError('AUTH_REQUIRED',401)}
async function lineSession(env:Env,subject:string){const session=random();const id=await rpc(env,'impjo_line_session',{p_subject:subject,p_hash:await digest(session)});return{session,id}}
async function actor(request:Request,env:Env){const token=getCookie(request,'staff');if(token){const user=await sb(env,'/auth/v1/user',undefined,token);if(!user.id)throw new ApiError('AUTH_REQUIRED',401);return await rpc(env,'impjo_staff_session_actor',{p_uid:user.id,p_session:sessionId(token)}) as unknown as string}const line=getCookie(request,'line');if(line){const id=await rpc(env,'impjo_session_actor',{p_hash:await digest(line)});if(id)return id as unknown as string}throw new ApiError('AUTH_REQUIRED',401)}
async function readBody(request:Request){if(!request.headers.get('content-type')?.startsWith('application/json'))throw new ApiError('JSON_REQUIRED',415);const text=await request.text();if(text.length>65536)throw new ApiError('REQUEST_TOO_LARGE',413);try{return JSON.parse(text) as Record<string,unknown>}catch{throw new ApiError('INVALID_JSON')}}
export async function verifyWebhook(raw:string,signature:string,secret:string){try{const bytes=Uint8Array.from(atob(signature),c=>c.charCodeAt(0));if(bytes.length!==32)return false;const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['verify']);return await crypto.subtle.verify('HMAC',key,bytes,new TextEncoder().encode(raw))}catch{return false}}
export function botReply(text:string,liffId:string){
 const command=text.trim().toUpperCase();
 const portal=liffId?`https://liff.line.me/${liffId}`:`${ORIGIN}/portal`;
 const quickReply={items:[{type:'action',action:{type:'message',label:'MESS · อัปเดตงาน',text:'MESS'}},{type:'action',action:{type:'message',label:'OPERATOR · สร้างงาน',text:'OPERATOR'}}]};
 const messages=command==='MESS'
  ?`MESS — อัปเดตสถานะงาน\nเปิดงานที่ได้รับมอบหมาย เลือก B/L แล้วกดรายงานเสร็จสมบูรณ์ หรือรายงานปัญหาพร้อมรายละเอียด\n${portal}\nต้องเข้าสู่ LINE และได้รับอนุมัติ MESS จาก ADMIN ก่อน`
  :command==='OPERATOR'
  ?`OPERATOR — สร้าง Job Order\nเข้าสู่ระบบด้วยอีเมลบัญชีทีมงาน แล้วเปิดฟอร์มสร้างงาน\n${ORIGIN}/jobs/new\nรองรับหลาย B/L และฐานข้อมูลสร้างเลข Job อัตโนมัติ\nหากกำลังใช้บัญชี LINE ให้ออกจากระบบก่อนเข้าสู่บัญชีทีมงาน`
  :`IMP Job Order\nพิมพ์รหัสเริ่มใช้งาน หรือเลือกปุ่มด้านล่าง:\nMESS — ดูงานและอัปเดตสถานะ\nOPERATOR — สร้าง Job Order\nรหัสเป็นการเลือกเมนู สิทธิ์จริงตรวจจากบัญชีและงานที่ได้รับมอบหมาย`;
 return {type:'text',text:messages,quickReply};
}
type ChatEvent={webhookEventId?:string;type:string;replyToken?:string;source?:{type?:string;userId?:string};message?:{type:string;text?:string};postback?:{data?:string}};
type ChatBL={id:string;number:string;status:string};
type ChatJob={id:string;number:string;bls:ChatBL[]};
const chatText=(text:string,actions:unknown[]=[])=>({type:'text',text,...(actions.length?{quickReply:{items:actions.map(action=>({type:'action',action}))}}:{})});
const chatButton=(label:string,data:string)=>({type:'postback',label:label.slice(0,20),data});
const chatStatus:Record<string,string>={PENDING_HANDOVER:'รอส่งมอบ',IN_PROGRESS:'กำลังดำเนินการ',COMPLETED:'เสร็จสมบูรณ์',ISSUE_REPORTED:'พบปัญหา'};
export async function messChat(env:Env,event:ChatEvent){
 const subject=event.source?.userId;
 if(event.source?.type!=='user'||!/^U[0-9a-f]{32}$/.test(subject||''))return chatText('กรุณาใช้แชตส่วนตัวกับ OA');
 const actorId=await rpc(env,'impjo_line_actor',{p_subject:subject}) as unknown as string;
 if(!actorId)return chatText(`กรุณาเข้าสู่ LINE และรอ ADMIN อนุมัติ MESS ก่อน\n${ORIGIN}/portal`);
 const me=await rpc(env,'impjo_api',{p_actor:actorId,p_action:'me',p_data:{}}) as unknown as {kind:string;state:string;roles:string[]};
 if(me.kind!=='LINE'||me.state!=='APPROVED'||!me.roles.includes('MESS'))return chatText('บัญชีนี้ยังไม่มีสิทธิ์ MESS ที่ได้รับอนุมัติ กรุณาติดต่อ ADMIN');
 const text=(event.message?.text||'').trim(),postback=event.postback?.data||'';
 const call=(action:string,data:unknown={})=>rpc(env,'impjo_api',{p_actor:actorId,p_action:action,p_data:data});
 // Each read and write goes through current SQL role/assignment checks, never a typed role.
 async function assignedBL(id:string){
  if(!/^[0-9a-f-]{36}$/.test(id))throw new ApiError('NOT_FOUND',404);
  const rows=await sb(env,`/rest/v1/impjo_bls?id=eq.${encodeURIComponent(id)}&select=job_id`) as unknown as {job_id:string}[];
  if(!rows[0])throw new ApiError('NOT_FOUND',404);
  const result=await call('detail',{id:rows[0].job_id}) as unknown as {jobs:ChatJob[]};
  const job=result.jobs[0],bl=job?.bls.find(b=>b.id===id);
  if(!bl)throw new ApiError('NOT_FOUND',404);
  return {job,bl};
 }
 const confirm=postback.match(/^mess-confirm:(\d{1,20})$/);
 if(confirm){
  const drafts=await sb(env,`/rest/v1/impjo_events?id=eq.${confirm[1]}&actor_id=eq.${actorId}&select=action,target_id,detail,created_at`) as unknown as {action:string;target_id:string;detail:string;created_at:string}[];
  const draft=drafts[0];
  if(!draft||!['CHAT_PROPOSE_COMPLETED','CHAT_PROPOSE_ISSUE_REPORTED'].includes(draft.action)||Date.now()-Date.parse(draft.created_at)>600000)return chatText('คำขอยืนยันหมดอายุหรือไม่ถูกต้อง กรุณาพิมพ์ MESS เพื่อเริ่มใหม่');
  const {job,bl}=await assignedBL(draft.target_id);
  if(bl.status!=='IN_PROGRESS')return chatText(`B/L ${bl.number} มีสถานะ ${chatStatus[bl.status]} แล้ว ไม่มีการบันทึกซ้ำ\nพิมพ์ MESS เพื่อดูงานล่าสุด`);
  const status=draft.action.slice('CHAT_PROPOSE_'.length);
  await call('status',{bl_id:bl.id,status,detail:draft.detail});
  return chatText(`บันทึกสำเร็จ\n${job.number}\nB/L ${bl.number}\nสถานะ: ${chatStatus[status]}${draft.detail?'\nรายละเอียด: '+draft.detail:''}\nเว็บและ Supabase ใช้ข้อมูลเดียวกัน`,[{type:'message',label:'ดูงานของฉัน',text:'MESS'},{type:'uri',label:'เปิดบนเว็บ',uri:ORIGIN+'/jobs/'+job.id}]);
 }
 const selection=postback.match(/^mess-select:([0-9a-f-]{36})$/);
 if(selection){
  const {job,bl}=await assignedBL(selection[1]);
  await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_INPUT_CLOSED',target_id:bl.id});
  return chatText(`${job.number}\nB/L ${bl.number}\nสถานะ: ${chatStatus[bl.status]}${bl.status==='IN_PROGRESS'?'\nเลือกรายงานผลด้านล่าง':'\nอัปเดตได้เฉพาะงานที่กำลังดำเนินการ'}`,bl.status==='IN_PROGRESS'?[chatButton('เสร็จสมบูรณ์','mess-propose:COMPLETED:'+bl.id),chatButton('แจ้งปัญหา','mess-issue:'+bl.id)]:[]);
 }
 const issuePrompt=postback.match(/^mess-issue:([0-9a-f-]{36})$/);
 if(issuePrompt){const {bl}=await assignedBL(issuePrompt[1]);if(bl.status!=='IN_PROGRESS')return chatText('รายการนี้ไม่ได้อยู่ระหว่างดำเนินการแล้ว กรุณาพิมพ์ MESS เพื่อดูงานล่าสุด');await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_EXPECT_ISSUE',target_id:bl.id});return chatText(`B/L ${bl.number}\nพิมพ์รายละเอียดปัญหาได้เลย เช่น นัดวันใหม่ (ไม่เกิน 2,000 ตัวอักษร)\nระบบจะให้ยืนยันก่อนบันทึก ไม่ต้องแนบรูป\nขั้นตอนนี้หมดอายุใน 10 นาที พิมพ์ ยกเลิก เพื่อออก`)}
 const complete=postback.match(/^mess-propose:COMPLETED:([0-9a-f-]{36})$/)||text.match(/^(?:เสร็จ|COMPLETED)\s+([0-9a-f-]{36})$/i);
 let issue=text.match(/^(?:ปัญหา|ISSUE)\s+([0-9a-f-]{36})(?:\s+([\s\S]*))?$/i);
 if(!postback&&!complete&&!issue&&!/^(?:MESS|งาน)(?:\s|$)/i.test(text)){
  if(/^(?:ยกเลิก|CANCEL)$/i.test(text)){await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_INPUT_CLOSED'});return chatText('ยกเลิกการกรอกรายละเอียดแล้ว พิมพ์ MESS เพื่อดูงาน');}
  const pending=await sb(env,`/rest/v1/impjo_events?actor_id=eq.${actorId}&action=in.(CHAT_EXPECT_ISSUE,CHAT_INPUT_CLOSED,CHAT_PROPOSE_COMPLETED,CHAT_PROPOSE_ISSUE_REPORTED)&order=id.desc&limit=1&select=action,target_id,created_at`) as unknown as {action:string;target_id:string;created_at:string}[];
  if(pending[0]?.action==='CHAT_EXPECT_ISSUE'&&Date.now()-Date.parse(pending[0].created_at)<=600000&&text)issue=['',pending[0].target_id,text] as unknown as RegExpMatchArray;
  else return botReply(text,env.LIFF_ID);
 }
 if(complete||issue){
  const id=(complete||issue)![1],detail=issue?(issue[2]||'').trim():'',status=issue?'ISSUE_REPORTED':'COMPLETED';
  if(issue&&!detail)return chatText('กรุณาระบุรายละเอียดปัญหาหลังรหัส B/L');
  if(detail.length>2000)return chatText('รายละเอียดปัญหายาวเกิน 2,000 ตัวอักษร กรุณาย่อแล้วส่งใหม่');
  const {job,bl}=await assignedBL(id);
  if(bl.status!=='IN_PROGRESS')return chatText(`B/L ${bl.number} มีสถานะ ${chatStatus[bl.status]} จึงไม่สามารถรายงานผลจากแชตได้`);
  // A proposal is an audit record, not a business status change. No new identity or schema is required.
  const drafts=await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_PROPOSE_'+status,target_id:bl.id,detail}) as unknown as {id:number}[];
  if(!drafts[0]?.id)throw new ApiError('SERVICE_UNAVAILABLE',503);
  return chatText(`ยืนยันรายงานผล?\n${job.number}\nB/L ${bl.number}\nสถานะใหม่: ${chatStatus[status]}${detail?'\nรายละเอียด: '+detail:''}\nยังไม่บันทึกจนกด “ยืนยันบันทึก” ภายใน 10 นาที`,[chatButton('ยืนยันบันทึก','mess-confirm:'+drafts[0].id),{type:'message',label:'กลับดูงาน',text:'MESS'}]);
 }
 if(postback.startsWith('mess-'))return chatText('คำสั่งไม่ถูกต้อง กรุณาพิมพ์ MESS เพื่อเริ่มใหม่');
 await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_INPUT_CLOSED'});
 const pageMatch=text.match(/^MESS\s+(\d+)$/i),search=text.replace(/^(?:MESS|งาน)\s*/i,'');
 const page=pageMatch?Math.max(1,Math.min(Number(pageMatch[1]),100000)):1;
 const result=await call('list',{page,size:5,status:'IN_PROGRESS',search:pageMatch?'':search}) as unknown as {jobs:ChatJob[];total:number};
 const bls=result.jobs.flatMap(job=>job.bls.filter(bl=>bl.status==='IN_PROGRESS').map(bl=>({job,bl})));
 if(!bls.length)return chatText('ไม่มี B/L ที่กำลังดำเนินการและได้รับมอบหมายให้คุณ\nพิมพ์ MESS เพื่อดูใหม่ หรือให้ ADMIN ตรวจการมอบหมาย');
 const shown=bls.slice(0,10);
 return chatText(`งาน MESS · หน้า ${page}\n${shown.map(({job,bl})=>job.number+' / '+bl.number).join('\n')}\nเลือก B/L ด้านล่างเพื่อรายงานผล\nค้นหา: MESS ตามด้วยเลข B/L หรือเลข Job${bls.length>10?'\nรายการมากกว่า 10 B/L กรุณาค้นหาให้เฉพาะเจาะจง':''}`,[...shown.map(({bl})=>chatButton(bl.number,'mess-select:'+bl.id)),...(page>1?[{type:'message',label:'หน้าก่อน',text:'MESS '+(page-1)}]:[]),...(page*5<result.total?[{type:'message',label:'หน้าถัดไป',text:'MESS '+(page+1)}]:[])]);
}
async function webhook(request:Request,env:Env){
 if(!env.LINE_MESSAGING_CHANNEL_SECRET||!env.LINE_MESSAGING_CHANNEL_ACCESS_TOKEN)return json({error:'WEBHOOK_NOT_CONFIGURED'},503);
 const raw=await request.text();if(raw.length>262144)return json({error:'REQUEST_TOO_LARGE'},413);
 if(!await verifyWebhook(raw,request.headers.get('x-line-signature')||'',env.LINE_MESSAGING_CHANNEL_SECRET))return json({error:'INVALID_SIGNATURE'},401);
 const payload=JSON.parse(raw) as {events?:ChatEvent[]};
 if(!Array.isArray(payload.events)||payload.events.length>100)return json({error:'INVALID_WEBHOOK'},400);
 for(const event of payload.events){
  if(!event.webhookEventId)continue;
  if(event.source?.type&&event.source.type!=='user')continue;
  const id=encodeURIComponent(event.webhookEventId);const existing=await sb(env,`/rest/v1/impjo_webhook_events?event_id=eq.${id}&select=state`) as unknown as {state:string}[];
  if(existing.some(v=>v.state==='DONE'))continue;
  if(!existing.length)await sb(env,'/rest/v1/impjo_webhook_events',{event_id:event.webhookEventId});
  if(event.replyToken&&(event.type==='follow'||event.type==='postback'||(event.type==='message'&&event.message?.type==='text'))){
   // Commands choose a workflow only; neither a typed role nor a display name grants access.
   if(event.source?.type&&event.source.type!=='user')continue;
   let message:unknown=botReply(event.message?.text||'',env.LIFF_ID);
   if(event.postback?.data?.startsWith('mess-')||(event.type==='message'&&event.message?.type==='text'&&!/^OPERATOR$/i.test((event.message.text||'').trim()))){
    try{message=await messChat(env,event)}catch(error){if(!(error instanceof ApiError))throw error;message=chatText(['ACCESS_DENIED','APPROVAL_REQUIRED','NOT_FOUND'].includes(error.message)?'ไม่มีสิทธิ์เข้าถึง B/L นี้ หรือถูกถอนการมอบหมาย กรุณาติดต่อ ADMIN':error.message==='INVALID_STATUS_TRANSITION'?'สถานะงานหรือสิทธิ์เปลี่ยนไปแล้ว กรุณาพิมพ์ MESS เพื่อดูข้อมูลล่าสุด':'ทำรายการไม่สำเร็จ กรุณาพิมพ์ MESS แล้วลองใหม่')}
   }
   const reply=await fetch('https://api.line.me/v2/bot/message/reply',{method:'POST',headers:{Authorization:`Bearer ${env.LINE_MESSAGING_CHANNEL_ACCESS_TOKEN}`,'Content-Type':'application/json'},body:JSON.stringify({replyToken:event.replyToken,messages:[message]}),signal:AbortSignal.timeout(10000)});
   if(!reply.ok&&reply.status!==400)throw new ApiError('LINE_REPLY_FAILED',503);
  }
  await sb(env,`/rest/v1/impjo_webhook_events?event_id=eq.${id}`,{state:'DONE',completed_at:new Date().toISOString()},undefined,'PATCH');
 }
 return json({ok:true});
}
export async function onRequest({request,env}:Ctx){try{
 const url=new URL(request.url);const path=url.pathname.replace(/^\/api\/?/,'');
 if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.SUPABASE_PUBLISHABLE_KEY)return json({error:'SETUP_REQUIRED'},503);
 if(path==='line/start'&&request.method==='GET'){
  if(!env.LINE_LOGIN_CHANNEL_ID||!env.LINE_LOGIN_CHANNEL_SECRET)throw new ApiError('LINE_NOT_CONFIGURED',503);
  const state=random(),nonce=random(),verifier=random();const bytes=new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier)));const challenge=btoa(String.fromCharCode(...bytes)).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  const auth=new URL('https://access.line.me/oauth2/v2.1/authorize');auth.search=new URLSearchParams({response_type:'code',client_id:env.LINE_LOGIN_CHANNEL_ID,redirect_uri:ORIGIN+'/api/line/callback',state,scope:'openid',nonce,code_challenge:challenge,code_challenge_method:'S256',bot_prompt:'normal'}).toString();
  const headers=new Headers({Location:auth.toString(),'Cache-Control':'no-store'});for(const [k,v] of [['state',state],['nonce',nonce],['verifier',verifier]])headers.append('Set-Cookie',cookie(k,v,600));return new Response(null,{status:302,headers});
 }
 if(path==='line/callback'&&request.method==='GET'){
  const state=getCookie(request,'state'),nonce=getCookie(request,'nonce'),verifier=getCookie(request,'verifier');
  if(!state||!nonce||!verifier||url.searchParams.get('state')!==state||!url.searchParams.get('code'))throw new ApiError('INVALID_LOGIN_STATE',401);
  const exchanged=await fetch('https://api.line.me/oauth2/v2.1/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',code:url.searchParams.get('code')!,redirect_uri:ORIGIN+'/api/line/callback',client_id:env.LINE_LOGIN_CHANNEL_ID,client_secret:env.LINE_LOGIN_CHANNEL_SECRET,code_verifier:verifier}),signal:AbortSignal.timeout(10000)});
  const tokens=await exchanged.json() as {id_token?:string};if(!exchanged.ok||!tokens.id_token)throw new ApiError('LINE_LOGIN_FAILED',401);
  const checked=await fetch('https://api.line.me/oauth2/v2.1/verify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({id_token:tokens.id_token,client_id:env.LINE_LOGIN_CHANNEL_ID,nonce}),signal:AbortSignal.timeout(10000)});
  const identity=await checked.json() as {iss?:string;aud?:string;exp?:number;sub?:string;nonce?:string};
  if(!checked.ok||identity.iss!=='https://access.line.me'||identity.aud!==env.LINE_LOGIN_CHANNEL_ID||identity.nonce!==nonce||!identity.exp||identity.exp<=Date.now()/1000||!/^U[0-9a-f]{32}$/.test(identity.sub||''))throw new ApiError('INVALID_LINE_TOKEN',401);
  const s=await lineSession(env,identity.sub!);const headers=new Headers({Location:ORIGIN+'/portal','Cache-Control':'no-store'});
  for(const c of [cookie('line',s.session,28800),cookie('staff','',0),cookie('state','',0),cookie('nonce','',0),cookie('verifier','',0)])headers.append('Set-Cookie',c);
  return new Response(null,{status:302,headers});
 }
 if(path==='config'&&request.method==='GET')return json({liffId:env.LIFF_ID||null,oa:'@110deiyl',lineChannel:env.LINE_LOGIN_CHANNEL_ID||null});
 if(path==='line/webhook'&&request.method==='POST')return await webhook(request,env);
 if(request.method==='POST'){
  if(request.headers.get('origin')!==ORIGIN||request.headers.get('x-imp-client')!=='web')return json({error:'ORIGIN_DENIED'},403);
  const data=await readBody(request);
  if(path==='auth/login'){
   const email=String(data.email||'').trim();const password=String(data.password||'');if(email.length>254||password.length>512||!email||!password)throw new ApiError('INVALID_CREDENTIALS');
   const session=await sb(env,'/auth/v1/token?grant_type=password',{email,password},env.SUPABASE_PUBLISHABLE_KEY);
   const user=session.user as {id:string;email_confirmed_at?:string};if(!user?.email_confirmed_at)throw new ApiError('EMAIL_CONFIRMATION_REQUIRED',403);
   const id=await rpc(env,'impjo_staff_session_actor',{p_uid:user.id,p_session:sessionId(String(session.access_token))});const me=await rpc(env,'impjo_api',{p_actor:id,p_action:'me',p_data:{}});
   return json({me},200,[cookie('staff',String(session.access_token),Math.min(Number(session.expires_in)||3600,3600)),cookie('line','',0)]);
  }
  if(path==='auth/signup'){
   const email=String(data.email||'').trim(),password=String(data.password||'');if(!email||email.length>254||password.length<12||password.length>512)throw new ApiError('USE_PASSWORD_12_CHARACTERS');
   await sb(env,`/auth/v1/signup?redirect_to=${encodeURIComponent(ORIGIN+'/login')}`,{email,password},env.SUPABASE_PUBLISHABLE_KEY);
   return json({message:'ตรวจสอบอีเมลเพื่อยืนยันบัญชี แล้วกลับมาเข้าสู่ระบบ ผู้ใช้ใหม่ต้องรอ ADMIN อนุมัติ'});
  }
  if(path==='auth/logout'){
   const line=getCookie(request,'line');if(line)await sb(env,`/rest/v1/impjo_sessions?token_hash=eq.${await digest(line)}`,{revoked_at:new Date().toISOString()},undefined,'PATCH');
   const token=getCookie(request,'staff');if(token)try{await sb(env,'/auth/v1/logout',{},token)}catch{/* Local cookie is still cleared. */}
   return json({ok:true},200,[cookie('staff','',0),cookie('line','',0)]);
  }
  if(path==='action'){
   const allowed=['list','detail','dashboard','create','people','approve','assign','assignments','status','audit'];const action=String(data.action||'');if(!allowed.includes(action))throw new ApiError('UNKNOWN_ACTION',404);
   const id=await actor(request,env);return json(await rpc(env,'impjo_api',{p_actor:id,p_action:action,p_data:data.data&&typeof data.data==='object'?data.data:{}}));
  }
 }
 if(path==='me'&&request.method==='GET')return json(await rpc(env,'impjo_api',{p_actor:await actor(request,env),p_action:'me',p_data:{}}));
 return json({error:'NOT_FOUND'},404);
}catch(error){if(error instanceof ApiError)return json({error:error.message},error.status);return json({error:'SERVICE_UNAVAILABLE'},503)}}