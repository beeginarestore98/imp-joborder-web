import{messCard,type CardPresentation}from'./mess-card.ts';
type Env={SUPABASE_URL:string;SUPABASE_SERVICE_ROLE_KEY:string;SUPABASE_PUBLISHABLE_KEY:string;LINE_LOGIN_CHANNEL_ID:string;LINE_LOGIN_CHANNEL_SECRET:string;LIFF_ID:string;LINE_MESSAGING_CHANNEL_SECRET:string;LINE_MESSAGING_CHANNEL_ACCESS_TOKEN:string};
type Ctx={request:Request;env:Env;params:Record<string,string|string[]>};
const ORIGIN='https://imp-joborder-web.pages.dev';
const loginReturn=(value:string|null)=>value==='/scan'||value==='/invite'?value:'/portal';
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
 if(!response.ok){const code=String(data.code||'');const known=['INVALID_SEARCH_FILTER','ACCOUNT_DELETED','ACCOUNT_DELETE_PENDING','INVITE_UNAVAILABLE','INVALID_INVITE','INVITE_WRONG_ACCOUNT','INVITE_ACCOUNT_HAS_ROLE','INVALID_EMAIL_CODE','AUTH_REQUIRED','APPROVAL_REQUIRED','ACCESS_DENIED','NOT_FOUND','INVALID_BL_LIST','INVALID_ROLE','CANNOT_CHANGE_SELF','INVALID_IDENTITY_ROLE','ASSIGNEE_NOT_APPROVED','INVALID_STATUS_TRANSITION','ISSUE_DETAIL_REQUIRED','DETAIL_TOO_LONG','INVALID_JOB_DATE','AMOUNT_REQUIRED','INVALID_AMOUNT','INVALID_CATALOG','STALE_JOB','STALE_STATUS','JOB_ARCHIVED','BL_REMOVAL_NOT_ALLOWED','INVALID_DATE_RANGE','EXPORT_TOO_LARGE','INVALID_RECIPIENT'];const msg=String(data.message||'');throw new ApiError(known.includes(msg)?msg:code==='23505'?'DUPLICATE_RECORD':path.startsWith('/auth/')?'AUTH_FAILED':'DATABASE_REQUEST_FAILED',path.startsWith('/auth/')||code==='28000'?401:code==='42501'?403:code==='P0002'?404:400)}
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
 const quickReply={items:[{type:'action',action:{type:'message',label:'MESS · อัปเดตงาน',text:'MESS'}},{type:'action',action:{type:'message',label:'OPERATOR · ส่งมอบ',text:'OPERATOR'}},{type:'action',action:{type:'message',label:'OUTSOURCE · ส่งมอบ',text:'OUTSOURCE'}}]};
 const messages=command==='MESS'
  ?`MESS — อัปเดตสถานะงาน\nเลือกผู้ประสานงานและ B/L เพื่อตรวจสอบความคืบหน้า รายงานผลสำเร็จ หรือแจ้งปัญหาพร้อมรายละเอียด\n${portal}\nเข้าสู่ LINE และรับสิทธิ์ MESS จากลิงก์หรือ QR คำเชิญของ ADMIN`
  :command==='OPERATOR'
  ?`OPERATOR — สร้าง Job Order\nเข้าสู่ระบบด้วยอีเมลบัญชีทีมงาน แล้วเปิดฟอร์มสร้างงาน\n${ORIGIN}/operator\nรองรับหลาย B/L และฐานข้อมูลสร้างเลข Job อัตโนมัติ\nหากกำลังใช้บัญชี MESS ให้กดปุ่มเข้าสู่ระบบทีมงานในหน้าฟอร์ม`
  :`IMP Job Order\nพิมพ์รหัสเริ่มใช้งาน หรือเลือกปุ่มด้านล่าง:\nMESS — ดูงานและอัปเดตสถานะ\n\nOPERATOR — ส่งมอบงาน / สร้าง Job\n\nOUTSOURCE — ดูงาน / อัปเดตสถานะ\nรหัสเป็นการเลือกเมนู สิทธิ์จริงตรวจจากบัญชีและบทบาทที่ได้รับในระบบ`;
 return {type:'text',text:messages,quickReply};
}
type ChatEvent={webhookEventId?:string;type:string;replyToken?:string;source?:{type?:string;userId?:string};message?:{type:string;text?:string};postback?:{data?:string}};
type ChatBL={id:string;number:string;status:string;can_report?:boolean};
type ChatJob={job_date:string|null;id:string;number:string;bls:ChatBL[]};
const chatText=(text:string,actions:unknown[]=[],presentation?:CardPresentation)=>({type:'text',text,...(presentation?{presentation}:{}),...(actions.length?{quickReply:{items:actions.map(action=>({type:'action',action}))}}:{})});
const workChat=(job:ChatJob,bl:ChatBL,text:string,actions:unknown[]=[],nextStatus?:string)=>chatText(text,actions,{current:{jobNumber:job.number,blNumber:bl.number,status:bl.status,jobDate:job.job_date},...(nextStatus?{nextStatus}:{})});
const chatButton=(label:string,data:string)=>({type:'postback',label:label.slice(0,20),data});
const chatStatus:Record<string,string>={PENDING_HANDOVER:'รอส่งมอบ',IN_PROGRESS:'กำลังดำเนินการ',COMPLETED:'เสร็จสมบูรณ์',ISSUE_REPORTED:'แจ้งปัญหา'};
export async function messChat(env:Env,event:ChatEvent){
 const subject=event.source?.userId;
 if(event.source?.type!=='user'||!/^U[0-9a-f]{32}$/.test(subject||''))return chatText('กรุณาใช้แชตส่วนตัวกับ LINE Official Account เพื่อดำเนินการ');
 const actorId=await rpc(env,'impjo_line_actor',{p_subject:subject}) as unknown as string;
 if(!actorId)return chatText(`กรุณาเข้าสู่ LINE แล้วเปิดลิงก์หรือ QR คำเชิญ MESS จาก ADMIN\n${ORIGIN}/portal`);
 const me=await rpc(env,'impjo_api',{p_actor:actorId,p_action:'me',p_data:{}}) as unknown as {kind:string;state:string;roles:string[];name?:string};
 if(me.kind!=='LINE'||me.state!=='APPROVED'||!me.roles.includes('MESS'))return me.state==='APPROVED'&&me.roles.includes('OUTSOURCE')?chatText('OUTSOURCE\n\nพิมพ์ OUTSOURCE เพื่อดูและอัปเดตงาน\nข้อมูลทุกงานดูได้บนเว็บ',[{type:'message',label:'ส่งมอบงาน',text:'OUTSOURCE'},{type:'uri',label:'ดูงานทั้งหมด',uri:ORIGIN+'/portal'}]):chatText('บัญชีนี้ยังไม่มีสิทธิ์ MESS กรุณาเปิดลิงก์หรือ QR คำเชิญจาก ADMIN');
 const text=(event.message?.text||'').trim(),postback=event.postback?.data||'';
 const today=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const call=(action:string,data:unknown={})=>rpc(env,'impjo_api',{p_actor:actorId,p_action:action,p_data:data});
 // Each read and write goes through current SQL role/assignment checks, never a typed role.
 async function assignedBL(id:string){
  if(!/^[0-9a-f-]{36}$/.test(id))throw new ApiError('NOT_FOUND',404);
  const rows=await sb(env,`/rest/v1/impjo_bls?id=eq.${encodeURIComponent(id)}&select=job_id`) as unknown as {job_id:string}[];
  if(!rows[0])throw new ApiError('NOT_FOUND',404);
  const result=await call('detail',{id:rows[0].job_id}) as unknown as {jobs:ChatJob[]};
  const job=result.jobs[0],bl=job?.bls.find(b=>b.id===id);
  if(!bl||!job.job_date||job.job_date>today||(job.job_date<today&&bl.status==='COMPLETED'))throw new ApiError('NOT_FOUND',404);
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
  return workChat(job,{...bl,status},`บันทึกสำเร็จ\n\nงาน: ${job.number}\nB/L: ${bl.number}\nสถานะ: ${chatStatus[status]}${draft.detail?'\nรายละเอียด: '+draft.detail:''}\n\nข้อมูลได้รับการบันทึกและแสดงผลบนเว็บไซต์แล้ว`,[{type:'message',label:'เลือกผู้ประสานงาน',text:'MESS'},{type:'uri',label:'เปิดบนเว็บ',uri:ORIGIN+'/jobs/'+job.id}]);
 }
 const selection=postback.match(/^mess-select:([0-9a-f-]{36})$/);
 if(selection){
  const {job,bl}=await assignedBL(selection[1]);
  await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_INPUT_CLOSED',target_id:bl.id});
  return workChat(job,bl,`${job.number}\n\nB/L: ${bl.number}\nสถานะ: ${chatStatus[bl.status]}${bl.status==='IN_PROGRESS'?(bl.can_report===true?'\nกรุณาเลือกรายงานผลการดำเนินงาน':'\nกรุณาโหลดรายการใหม่เพื่อตรวจสิทธิ์'):'\nอัปเดตได้เฉพาะงานที่กำลังดำเนินการ'}`,bl.status==='IN_PROGRESS'&&bl.can_report===true?[chatButton('เสร็จสมบูรณ์','mess-propose:COMPLETED:'+bl.id),chatButton('แจ้งปัญหา','mess-issue:'+bl.id)]:[]);
 }
 const issuePrompt=postback.match(/^mess-issue:([0-9a-f-]{36})$/);
 if(issuePrompt){const {bl}=await assignedBL(issuePrompt[1]);if(bl.status!=='IN_PROGRESS')return chatText('รายการนี้ไม่ได้อยู่ระหว่างดำเนินการแล้ว กรุณาพิมพ์ MESS เพื่อดูงานล่าสุด');await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_EXPECT_ISSUE',target_id:bl.id});return chatText(`เลือกปัญหา\n\nB/L: ${bl.number}\nกดปัญหาเริ่มต้น หรือพิมพ์รายละเอียดอื่นได้ (ไม่เกิน 2,000 ตัวอักษร)\nระบบจะให้ยืนยันก่อนบันทึก ภายใน 10 นาที`,[chatButton('แจ้งวันนัดใหม่','mess-preset:RESCHEDULE:'+bl.id),chatButton('แก้ไขเอกสาร','mess-preset:DOCUMENT:'+bl.id),{type:'message',label:'ยกเลิก',text:'MESS'}])}
 const complete=postback.match(/^mess-propose:COMPLETED:([0-9a-f-]{36})$/)||text.match(/^(?:เสร็จ|COMPLETED)\s+([0-9a-f-]{36})$/i);
 const preset=postback.match(/^mess-preset:(RESCHEDULE|DOCUMENT):([0-9a-f-]{36})$/);
 let issue=text.match(/^(?:ปัญหา|ISSUE)\s+([0-9a-f-]{36})(?:\s+([\s\S]*))?$/i);
 if(preset)issue=['',preset[2],preset[1]==='RESCHEDULE'?'แจ้งวันนัดใหม่':'แก้ไขเอกสาร'] as unknown as RegExpMatchArray;
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
  return workChat(job,bl,`ยืนยันรายงานผล\n\nงาน: ${job.number}\nB/L: ${bl.number}\nสถานะใหม่: ${chatStatus[status]}${detail?'\nรายละเอียด: '+detail:''}\n\nระบบยังไม่บันทึกข้อมูล กรุณาตรวจสอบก่อนกด “ยืนยันบันทึก”\nกรุณายืนยันภายใน 10 นาที`,[chatButton('ยืนยันบันทึก','mess-confirm:'+drafts[0].id),{type:'message',label:'กลับดูงาน',text:'MESS'}],status);
 }
 const contactPage=postback.match(/^mess-contacts:(\d{1,6})$/);
 const contactJobs=postback.match(/^mess-contact:([0-9a-f-]{36}):(\d{1,6})$/);
 if(postback&&!contactPage&&!contactJobs)return chatText('คำสั่งไม่ถูกต้อง กรุณาพิมพ์ MESS เพื่อเริ่มใหม่');
 await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_INPUT_CLOSED'});
 if(!contactJobs){
  const page=contactPage?Math.max(1,Number(contactPage[1])):1;
  const result=await rpc(env,'impjo_mess_browse',{p_actor:actorId,p_data:{mode:'contacts',page}}) as unknown as {total:number;contacts:{contact:string;key:string;bl_count:number}[]};
  return chatText('MESS · เลือกผู้ประสานงาน (Contact Name)\n\nรายการงานประจำวันและงานค้างดำเนินการของทุกคน\n'+(result.contacts.length?result.contacts.map((c,i)=>(i+1)+'. '+c.contact+' · '+c.bl_count+' B/L').join('\n'):'ไม่พบงานปัจจุบันในระบบ · รายการที่ยังไม่ระบุวันที่งานจะไม่แสดง')+'\n\nกรุณาเลือกผู้ประสานงานเพื่อดูรายการงาน · หน้า '+page,[...result.contacts.map(c=>chatButton(c.contact,'mess-contact:'+c.key+':1')),...(page>1?[chatButton('หน้าก่อน','mess-contacts:'+(page-1))]:[]),...(page*10<result.total?[chatButton('หน้าถัดไป','mess-contacts:'+(page+1))]:[]),{type:'message',label:'รีเฟรชรายชื่อ',text:'MESS'}]);
 }
 const key=contactJobs[1],page=Math.max(1,Number(contactJobs[2]));
 const result=await rpc(env,'impjo_mess_browse',{p_actor:actorId,p_data:{mode:'bls',contact_key:key,page}}) as unknown as {total:number;bls:{id:string;number:string;status:string;job_number:string;job_date:string;contact:string;can_report:boolean}[]};
 return chatText('Contact: '+(result.bls[0]?.contact||'ไม่พบงานปัจจุบัน')+'\nทั้งหมด '+result.total+' B/L · หน้า '+page+'\n\n'+result.bls.map((b,i)=>(i+1)+'. '+b.job_number+'\nB/L: '+b.number+'\nวันที่งาน: '+b.job_date+'\nสถานะ: '+chatStatus[b.status]+'\n'+(b.can_report?'ผู้ใช้งาน MESS สามารถรายงานผลได้':'ดูข้อมูล')).join('\n\n')+'\n\nเลือก B/L เพื่อดูรายละเอียด',[...result.bls.map(b=>chatButton(b.number,'mess-select:'+b.id)),...(page>1?[chatButton('หน้าก่อน','mess-contact:'+key+':'+(page-1))]:[]),...(page*5<result.total?[chatButton('หน้าถัดไป','mess-contact:'+key+':'+(page+1))]:[]),{type:'message',label:'เลือกผู้ประสานงาน',text:'MESS'}],{items:result.bls.map(b=>({jobNumber:b.job_number,blNumber:b.number,status:b.status,jobDate:b.job_date,action:chatButton(b.number,'mess-select:'+b.id)}))});
}
export async function handoverChat(env:Env,event:ChatEvent){
 const subject=event.source?.userId;
 if(event.source?.type!=='user'||!/^U[0-9a-f]{32}$/.test(subject||''))return chatText('กรุณาใช้แชตส่วนตัวกับ LINE Official Account เพื่อดำเนินการ');
 const text=(event.message?.text||'').trim(),postback=event.postback?.data||'';
 const mode=(postback.split(':')[1]||text.split(/\s/)[0]).toUpperCase()==='OUTSOURCE'?'OUTSOURCE':'OPERATOR';
 const actorId=await rpc(env,mode==='OPERATOR'?'impjo_operator_actor':'impjo_line_actor',{p_subject:subject}) as unknown as string;
 if(!actorId)return chatText(mode==='OPERATOR'?`ยังไม่มีสิทธิ์ OPERATOR ใน LINE\n\nกรุณาเปิดลิงก์หรือสแกน QR คำเชิญ OPERATOR จากผู้ดูแลระบบ แล้วเข้าสู่บัญชี LINE ของท่านเพื่อรับสิทธิ์\n\nสำหรับบัญชีทีมงานเดิมที่ผูกบัญชี LINE กรุณาติดต่อผู้ดูแลระบบเพื่อตรวจสอบสิทธิ์\n\n${ORIGIN}/line-link`:`กรุณาเข้าสู่ LINE และรับสิทธิ์ OUTSOURCE ผ่านลิงก์หรือ QR คำเชิญจากผู้ดูแลระบบ\n\n${ORIGIN}/portal`);
 const me=await rpc(env,'impjo_api',{p_actor:actorId,p_action:'me',p_data:{}}) as unknown as {kind:string;state:string;roles:string[]};
 if(me.state!=='APPROVED'||!me.roles.includes(mode)||(mode==='OUTSOURCE'&&me.kind!=='LINE'))return chatText(`บัญชีนี้ยังไม่มีสิทธิ์ ${mode} กรุณาติดต่อ ADMIN`);
 const call=(action:string,data:unknown={})=>rpc(env,'impjo_api',{p_actor:actorId,p_action:action,p_data:data});
 async function readBL(id:string){
  const rows=await sb(env,`/rest/v1/impjo_bls?id=eq.${encodeURIComponent(id)}&select=job_id`) as unknown as {job_id:string}[];
  if(!rows[0])throw new ApiError('NOT_FOUND',404);
  const result=await call('detail',{id:rows[0].job_id}) as unknown as {jobs:ChatJob[]};
  const job=result.jobs[0],bl=job?.bls.find(b=>b.id===id);if(!bl)throw new ApiError('NOT_FOUND',404);
  return{job,bl};
 }
 const confirmation=postback.match(/^handover-confirm:(OPERATOR|OUTSOURCE):(\d{1,20})$/);
 if(confirmation){
  const drafts=await sb(env,`/rest/v1/impjo_events?id=eq.${confirmation[2]}&actor_id=eq.${actorId}&action=eq.CHAT_PROPOSE_HANDOVER&select=target_id,created_at,detail`) as unknown as {target_id:string;created_at:string;detail:string}[];
  const draft=drafts[0];
  if(!draft||Date.now()-Date.parse(draft.created_at)>600000||draft.detail!==subject)return chatText('คำขอยืนยันหมดอายุหรือไม่ถูกต้อง\nกรุณาพิมพ์ '+mode+' เพื่อเริ่มใหม่');
  const {job,bl}=await readBL(draft.target_id);
  if(bl.status!=='PENDING_HANDOVER')return chatText(`B/L: ${bl.number}\nสถานะ: ${chatStatus[bl.status]}\n\nไม่มีการบันทึกซ้ำ`,[{type:'message',label:'ดูงานรอส่งมอบ',text:mode}]);
  await call('status',{bl_id:bl.id,status:'IN_PROGRESS',detail:'ส่งมอบผ่าน LINE ('+mode+')'});
  return workChat(job,{...bl,status:'IN_PROGRESS'},`ส่งมอบงานสำเร็จ\n\nงาน: ${job.number}\nB/L: ${bl.number}\nสถานะ: กำลังดำเนินการ\n\nMESS ที่อนุมัติแล้วทุกคนสามารถรายงานผลต่อได้`,[{type:'message',label:'ดูงานรอส่งมอบ',text:mode},{type:'uri',label:'เปิดงานบนเว็บ',uri:ORIGIN+'/jobs/'+job.id}]);
 }
 const updateConfirm=postback.match(/^handover-update:(OPERATOR|OUTSOURCE):(\d{1,20})$/);
 if(updateConfirm){
  const drafts=await sb(env,`/rest/v1/impjo_events?id=eq.${updateConfirm[2]}&actor_id=eq.${actorId}&action=eq.CHAT_PROPOSE_STATUS&select=target_id,detail,created_at`) as unknown as {target_id:string;detail:string;created_at:string}[];
  const draft=drafts[0];let data:{subject:string;mode:string;status:string;old:string;detail:string}|null=null;
  try{data=JSON.parse(draft?.detail||'null')}catch{/* An invalid audit payload cannot authorize a write. */}
  if(!draft||!data||data.subject!==subject||data.mode!==mode||!chatStatus[data.status]||Date.now()-Date.parse(draft.created_at)>600000)return chatText('คำขอยืนยันหมดอายุหรือไม่ถูกต้อง กรุณาพิมพ์ '+mode+' ใหม่');
  const {job,bl}=await readBL(draft.target_id);
  if(bl.status!==data.old)return chatText('สถานะเปลี่ยนแล้ว: '+chatStatus[bl.status]+'\nกรุณาเลือกรายการใหม่ ไม่มีการบันทึกทับ');
  await call('status',{bl_id:bl.id,status:data.status,detail:data.detail,expected_status:data.old});
  return workChat(job,{...bl,status:data.status},'อัปเดตสถานะสำเร็จ\n\nงาน: '+job.number+'\nB/L: '+bl.number+'\n'+chatStatus[data.old]+' → '+chatStatus[data.status]+'\n\nข้อมูลและประวัติการดำเนินงานได้รับการบันทึกบนเว็บไซต์แล้ว',[{type:'message',label:'ดูรายการล่าสุด',text:mode},{type:'uri',label:'เปิดบนเว็บ',uri:ORIGIN+'/jobs/'+job.id}]);
 }
 const selection=postback.match(/^handover-select:(OPERATOR|OUTSOURCE):([0-9a-f-]{36})$/);
 if(selection){
  const {job,bl}=await readBL(selection[2]);
  await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_STATUS_INPUT_CLOSED',target_id:bl.id});
  return workChat(job,bl,job.number+'\nB/L: '+bl.number+'\nสถานะ: '+chatStatus[bl.status]+(bl.status==='COMPLETED'?'\nงานเสร็จแล้ว สามารถเปิดกลับมาทำต่อได้':'')+'\n\nกรุณาเลือกสถานะใหม่ที่ต้องการบันทึก',[...Object.keys(chatStatus).filter(status=>status!==bl.status).map(status=>chatButton(status==='IN_PROGRESS'?'ส่งมอบ / ดำเนินการ':chatStatus[status],'handover-propose:'+mode+':'+status+':'+bl.id)),{type:'message',label:'กลับรายการ',text:mode}]);
 }
 const proposal=postback.match(/^handover-propose:(OPERATOR|OUTSOURCE):(PENDING_HANDOVER|IN_PROGRESS|COMPLETED|ISSUE_REPORTED):([0-9a-f-]{36})$/);
 const statusPreset=postback.match(/^handover-preset:(OPERATOR|OUTSOURCE):(RESCHEDULE|DOCUMENT):([0-9a-f-]{36})$/);
 const issue=text.match(/^(?:OPERATOR|OUTSOURCE)\s+ปัญหา\s+([\s\S]+)$/i);
 let updateId=proposal?.[3],newStatus=proposal?.[2],detail='';
 if(statusPreset){updateId=statusPreset[3];newStatus='ISSUE_REPORTED';detail=statusPreset[2]==='RESCHEDULE'?'แจ้งวันนัดใหม่':'แก้ไขเอกสาร';}
 if(issue){
  const prompts=await sb(env,`/rest/v1/impjo_events?actor_id=eq.${actorId}&action=in.(CHAT_STATUS_EXPECT_ISSUE,CHAT_STATUS_INPUT_CLOSED,CHAT_PROPOSE_STATUS)&order=id.desc&limit=1&select=action,target_id,detail,created_at`) as unknown as {action:string;target_id:string;detail:string;created_at:string}[];
  const prompt=prompts[0];let proof:{subject:string;mode:string}|null=null;try{proof=JSON.parse(prompt?.detail||'null')}catch{}
  if(!prompt||prompt.action!=='CHAT_STATUS_EXPECT_ISSUE'||proof?.subject!==subject||proof?.mode!==mode||Date.now()-Date.parse(prompt.created_at)>600000)return chatText('กรุณาเลือก B/L แล้วกด พบปัญหา ก่อนส่งรายละเอียด');
  updateId=prompt.target_id;newStatus='ISSUE_REPORTED';detail=issue[1].trim();
  if(!detail||detail.length>2000)return chatText('กรุณาระบุรายละเอียดปัญหา 1–2,000 ตัวอักษร');
 }
 if(updateId&&newStatus){
  const {job,bl}=await readBL(updateId);
  if(bl.status===newStatus)return chatText('รายการนี้มีสถานะ '+chatStatus[bl.status]+' อยู่แล้ว');
  if(newStatus==='ISSUE_REPORTED'&&!issue&&!statusPreset){await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_STATUS_EXPECT_ISSUE',target_id:bl.id,detail:JSON.stringify({subject,mode})});return chatText('B/L: '+bl.number+'\n\nเลือกปัญหาเริ่มต้นด้านล่าง หรือพิมพ์ '+mode+' ปัญหา ตามด้วยรายละเอียด\nเช่น '+mode+' ปัญหา เอกสารยังไม่พร้อม\n\nไม่ต้องพิมพ์เลข B/L · หมดอายุใน 10 นาที',[chatButton('แจ้งวันนัดใหม่','handover-preset:'+mode+':RESCHEDULE:'+bl.id),chatButton('แก้ไขเอกสาร','handover-preset:'+mode+':DOCUMENT:'+bl.id),{type:'message',label:'ยกเลิก',text:mode}]);}
  const drafts=await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_PROPOSE_STATUS',target_id:bl.id,detail:JSON.stringify({subject,mode,status:newStatus,old:bl.status,detail})}) as unknown as {id:number}[];
  if(!drafts[0]?.id)throw new ApiError('SERVICE_UNAVAILABLE',503);
  return workChat(job,bl,'ยืนยันเปลี่ยนสถานะ\n\nงาน: '+job.number+'\nB/L: '+bl.number+'\n'+chatStatus[bl.status]+' → '+chatStatus[newStatus]+(bl.status==='COMPLETED'?'\n⚠️ เปิดหรือเปลี่ยนงานที่เสร็จแล้ว':'')+(detail?'\nรายละเอียด: '+detail:'')+'\n\nกรุณาตรวจสอบและยืนยันภายใน 10 นาที ข้อมูลยังไม่ถูกเปลี่ยนแปลง',[chatButton('ยืนยันบันทึก','handover-update:'+mode+':'+drafts[0].id),{type:'message',label:'ยกเลิก',text:mode}],newStatus);
 }
 if(postback.startsWith('handover-'))return chatText('คำสั่งไม่ถูกต้อง กรุณาพิมพ์ '+mode+' ใหม่');
 await sb(env,'/rest/v1/impjo_events',{actor_id:actorId,action:'CHAT_STATUS_INPUT_CLOSED'});
 const match=text.match(/^(OPERATOR|OUTSOURCE)(?:\s+(.*))?$/i),query=match?.[2]||'';
 const page=/^\d+$/.test(query)?Math.max(1,Math.min(Number(query),100000)):1;
 const result=await rpc(env,'impjo_handover_list',{p_actor:actorId,p_page:page,p_search:page===1&&!/^\d+$/.test(query)?query:''}) as unknown as {total:number;bls:{id:string;number:string;status:string;job_number:string;job_date:string|null}[]};
 const actions:unknown[]=[...result.bls.map(bl=>chatButton(bl.number,`handover-select:${mode}:${bl.id}`)),...(page>1?[{type:'message',label:'หน้าก่อน',text:mode+' '+(page-1)}]:[]),...(page*5<result.total?[{type:'message',label:'หน้าถัดไป',text:mode+' '+(page+1)}]:[])];
 if(mode==='OPERATOR')actions.push({type:'uri',label:'สร้าง Job Order',uri:ORIGIN+'/operator'});
 return chatText(`อัปเดตสถานะงาน · ${mode}\nหน้า ${page} · ทั้งหมด ${result.total} B/L\n\n${result.bls.length?result.bls.map((bl,i)=>`${i+1}. ${bl.job_number}\nB/L: ${bl.number}\nวันที่งาน: ${bl.job_date||'ยังไม่กำหนด'}\nสถานะ: ${chatStatus[bl.status]}`).join('\n\n'):'ไม่พบงาน'}\n\nกรุณาเลือก B/L เพื่อตรวจสอบรายละเอียดและปรับปรุงสถานะ\nค้นหา: ${mode} ตามด้วยเลข Job หรือ B/L`,actions,{role:mode,items:result.bls.map(bl=>({jobNumber:bl.job_number,blNumber:bl.number,status:bl.status,jobDate:bl.job_date,action:chatButton(bl.number,`handover-select:${mode}:${bl.id}`)}))});
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
   const command=(event.message?.text||'').trim(),link=command.match(/^(?:ผูกบัญชี|LINK)\s+([0-9a-f]{64})$/i);
   if(link){
    try{await rpc(env,'impjo_claim_team_link',{p_subject:event.source?.userId,p_hash:await digest(link[1])});message=chatText('✅ ส่งคำขอผูกบัญชีแล้ว\n\nกรุณารอ ADMIN อนุมัติในหน้าเว็บ\nเมื่ออนุมัติแล้ว พิมพ์ OPERATOR เพื่อส่งมอบงาน')}
    catch(error){if(!(error instanceof ApiError))throw error;message=chatText(`ผูกบัญชีไม่สำเร็จ\n\nรหัสอาจหมดอายุ ใช้แล้ว หรือบัญชีมีการผูกอยู่\nกรุณาเข้าสู่ LINE Portal ก่อน แล้วสร้างรหัสใหม่จากบัญชีทีมงาน\n${ORIGIN}/line-link`)}
   }else if(event.postback?.data?.startsWith('handover-')||/^(OPERATOR|OUTSOURCE)(?:\s|$)/i.test(command)){
    try{message=messCard(await handoverChat(env,event),(event.postback?.data?.split(':')[1]||command.split(/\s/)[0]).toUpperCase()==='OUTSOURCE'?'OUTSOURCE':'OPERATOR')}catch(error){if(!(error instanceof ApiError))throw error;message=chatText('ไม่สามารถปรับปรุงสถานะงานได้\n\nสถานะงานหรือสิทธิ์การใช้งานอาจมีการเปลี่ยนแปลง\nพิมพ์ OPERATOR หรือ OUTSOURCE เพื่อดูข้อมูลล่าสุด')}
   }else if(event.postback?.data?.startsWith('mess-')||(event.type==='message'&&event.message?.type==='text')){
    try{message=messCard(await messChat(env,event))}catch(error){if(!(error instanceof ApiError))throw error;message=chatText(['ACCESS_DENIED','APPROVAL_REQUIRED','NOT_FOUND'].includes(error.message)?'ไม่พบ B/L หรือไม่มีสิทธิ์ดำเนินการ กรุณาตรวจสอบข้อมูลกับผู้ดูแลระบบ':error.message==='INVALID_STATUS_TRANSITION'?'สถานะงานหรือสิทธิ์เปลี่ยนไปแล้ว กรุณาพิมพ์ MESS เพื่อดูข้อมูลล่าสุด':'ทำรายการไม่สำเร็จ กรุณาพิมพ์ MESS แล้วลองใหม่')}
   }
   if((message as {type?:string}).type==='text')message=messCard(message as Parameters<typeof messCard>[0],'JOB ORDER');
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
  const headers=new Headers({Location:auth.toString(),'Cache-Control':'no-store'});for(const [k,v] of [['state',state],['nonce',nonce],['verifier',verifier],['next',loginReturn(url.searchParams.get('next'))]])headers.append('Set-Cookie',cookie(k,v,600));return new Response(null,{status:302,headers});
 }
 if(path==='line/callback'&&request.method==='GET'){
  const state=getCookie(request,'state'),nonce=getCookie(request,'nonce'),verifier=getCookie(request,'verifier');
  if(!state||!nonce||!verifier||url.searchParams.get('state')!==state||!url.searchParams.get('code'))throw new ApiError('INVALID_LOGIN_STATE',401);
  const exchanged=await fetch('https://api.line.me/oauth2/v2.1/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',code:url.searchParams.get('code')!,redirect_uri:ORIGIN+'/api/line/callback',client_id:env.LINE_LOGIN_CHANNEL_ID,client_secret:env.LINE_LOGIN_CHANNEL_SECRET,code_verifier:verifier}),signal:AbortSignal.timeout(10000)});
  const tokens=await exchanged.json() as {id_token?:string};if(!exchanged.ok||!tokens.id_token)throw new ApiError('LINE_LOGIN_FAILED',401);
  const checked=await fetch('https://api.line.me/oauth2/v2.1/verify',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({id_token:tokens.id_token,client_id:env.LINE_LOGIN_CHANNEL_ID,nonce}),signal:AbortSignal.timeout(10000)});
  const identity=await checked.json() as {iss?:string;aud?:string;exp?:number;sub?:string;nonce?:string};
  if(!checked.ok||identity.iss!=='https://access.line.me'||identity.aud!==env.LINE_LOGIN_CHANNEL_ID||identity.nonce!==nonce||!identity.exp||identity.exp<=Date.now()/1000||!/^U[0-9a-f]{32}$/.test(identity.sub||''))throw new ApiError('INVALID_LINE_TOKEN',401);
  const s=await lineSession(env,identity.sub!);const headers=new Headers({Location:ORIGIN+loginReturn(getCookie(request,'next')),'Cache-Control':'no-store'});
  for(const c of [cookie('line',s.session,28800),cookie('staff','',0),cookie('state','',0),cookie('nonce','',0),cookie('verifier','',0),cookie('next','',0)])headers.append('Set-Cookie',c);
  return new Response(null,{status:302,headers});
 }
 if(path==='config'&&request.method==='GET')return json({liffId:env.LIFF_ID||null,oa:'@110deiyl',lineChannel:env.LINE_LOGIN_CHANNEL_ID||null});
 if(path==='line/webhook'&&request.method==='POST')return await webhook(request,env);
 if(request.method==='POST'){
  if(request.headers.get('origin')!==ORIGIN||request.headers.get('x-imp-client')!=='web')return json({error:'ORIGIN_DENIED'},403);
  const data=await readBody(request);
  if(path==='invite/inspect'){
   const token=String(data.token||'');if(!/^[0-9a-f]{64}$/.test(token))throw new ApiError('INVITE_UNAVAILABLE',404);
   return json(await rpc(env,'impjo_invite',{p_actor:null,p_action:'inspect',p_data:{hash:await digest(token)}}));
  }
  if(path==='auth/login'){
   const email=String(data.email||'').trim();const password=String(data.password||'');if(email.length>254||password.length>512||!email||!password)throw new ApiError('INVALID_CREDENTIALS');
   const session=await sb(env,'/auth/v1/token?grant_type=password',{email,password},env.SUPABASE_PUBLISHABLE_KEY);
   const user=session.user as {id:string;email_confirmed_at?:string};if(!user?.email_confirmed_at)throw new ApiError('EMAIL_CONFIRMATION_REQUIRED',403);
   const id=await rpc(env,'impjo_staff_session_actor',{p_uid:user.id,p_session:sessionId(String(session.access_token))});const me=await rpc(env,'impjo_api',{p_actor:id,p_action:'me',p_data:{}});
   return json({me},200,[cookie('staff',String(session.access_token),Math.min(Number(session.expires_in)||3600,3600)),cookie('line','',0)]);
  }
  if(path==='auth/signup'){
   const email=String(data.email||'').trim(),password=String(data.password||'');if(!email||email.length>254||password.length<12||password.length>512)throw new ApiError('USE_PASSWORD_12_CHARACTERS');
   const registration=await sb(env,`/auth/v1/signup?redirect_to=${encodeURIComponent(ORIGIN+'/login')}`,{email,password},env.SUPABASE_PUBLISHABLE_KEY);
   const user=registration.user as {id?:string}|undefined;
   if(user?.id)try{await rpc(env,'impjo_register_pending',{p_uid:user.id})}catch{/* Duplicate-signup responses may conceal an existing user. Never grant access here. */}
   return json({message:'ลงทะเบียนแล้ว กรุณายืนยันอีเมลตามลิงก์ในอีเมล แล้วกลับมาเข้าสู่ระบบและเปิดลิงก์คำเชิญจาก ADMIN เพื่อรับสิทธิ์ทันที'});
  }
  if(path==='auth/logout'){
   const line=getCookie(request,'line');if(line)await sb(env,`/rest/v1/impjo_sessions?token_hash=eq.${await digest(line)}`,{revoked_at:new Date().toISOString()},undefined,'PATCH');
   const token=getCookie(request,'staff');if(token)try{await sb(env,'/auth/v1/logout',{},token)}catch{/* Local cookie is still cleared. */}
   return json({ok:true},200,[cookie('staff','',0),cookie('line','',0)]);
  }
  if(path==='action'){
   const requested=String(data.action||'');
   if(requested==='search_jobs')return json(await rpc(env,'impjo_search_jobs',{p_actor:await actor(request,env),p_data:data.data||{}}));
   if(requested==='delete_job'){const input=data.data&&typeof data.data==='object'?data.data as Record<string,unknown>:{};return json(await rpc(env,'impjo_delete_job',{p_actor:await actor(request,env),p_id:input.id,p_version:input.version}));}
   if(requested==='delete_account'||requested==='account_deletion_list'){
    const id=await actor(request,env);const input=data.data&&typeof data.data==='object'?data.data as Record<string,unknown>:{};
    if(requested==='account_deletion_list')return json(await rpc(env,'impjo_account_admin',{p_actor:id,p_action:'list',p_target:null}));
    const target=String(input.id||'');if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(target))throw new ApiError('NOT_FOUND',404);
    const pending=await rpc(env,'impjo_account_admin',{p_actor:id,p_action:'prepare',p_target:target}) as unknown as {auth_user_id:string|null;completed:boolean};
    if(pending.auth_user_id&&!pending.completed){
     const headers:Record<string,string>={apikey:env.SUPABASE_SERVICE_ROLE_KEY,'Content-Type':'application/json'};
     if(env.SUPABASE_SERVICE_ROLE_KEY.startsWith('eyJ'))headers.Authorization='Bearer '+env.SUPABASE_SERVICE_ROLE_KEY;
     try{const res=await fetch(env.SUPABASE_URL+'/auth/v1/admin/users/'+encodeURIComponent(pending.auth_user_id),{method:'DELETE',headers,body:JSON.stringify({should_soft_delete:false}),signal:AbortSignal.timeout(15000)});
      if(!res.ok){const body=await res.json() as {code?:string};if(res.status!==404||body.code!=='user_not_found')throw new Error('Auth deletion incomplete')}
     }catch{throw new ApiError('ACCOUNT_DELETE_PENDING',503)}
    }
    await rpc(env,'impjo_account_admin',{p_actor:id,p_action:'finish',p_target:target});
    return json({ok:true,deleted:true});
   }
   if(requested.startsWith('invite_')){
    const op=requested.slice(7);if(!['create','list','revoke','redeem'].includes(op))throw new ApiError('UNKNOWN_ACTION',404);
    const input=data.data&&typeof data.data==='object'?data.data as Record<string,unknown>:{};
    const id=await actor(request,env);
    const token=op==='create'?random():op==='redeem'?String(input.token||''):null;
    if(token!==null&&!/^[0-9a-f]{64}$/.test(token))throw new ApiError('INVITE_UNAVAILABLE',404);
    const payload=op==='create'?{hash:await digest(token!),kind:input.kind,role:input.role,label:input.label}:op==='redeem'?{hash:await digest(token!)}:{id:input.id};
    const result=await rpc(env,'impjo_invite',{p_actor:id,p_action:op,p_data:payload});
    return json(op==='create'?{...result,token}:result);
   }
   if(requested.startsWith('catalog_')){const op=requested.slice(8);if(!['list','save','archive'].includes(op))throw new ApiError('UNKNOWN_ACTION',404);return json(await rpc(env,'impjo_catalog_api',{p_actor:await actor(request,env),p_action:op,p_data:data.data||{}}));}
   if(['edit_job','archived_jobs','export_jobs'].includes(requested)){const id=await actor(request,env);return json(await rpc(env,'impjo_manage',{p_actor:id,p_action:requested,p_data:data.data||{}}));}
   if(requested.startsWith('report_')){const op=requested.slice(7);if(!['settings','enabled','recipient','preview'].includes(op))throw new ApiError('UNKNOWN_ACTION',404);const id=await actor(request,env);return json(await rpc(env,'impjo_reports',{p_actor:id,p_action:op,p_data:data.data||{}}));}
   if(requested.startsWith('line_link_')){
    const id=await actor(request,env),op=requested.slice('line_link_'.length);
    if(!['create_code','mine','list','approve','revoke'].includes(op))throw new ApiError('UNKNOWN_ACTION',404);
    const code=op==='create_code'?random():null;
    const result=await rpc(env,'impjo_team_link',{p_actor:id,p_action:op,p_data:code?{hash:await digest(code)}:data.data||{}});
    return json(code?{code,expires_in:600}:result);
   }
   const allowed=['list','detail','dashboard','create','people','approve','assign','assignments','status','audit','set_job_date'];const action=String(data.action||'');if(!allowed.includes(action))throw new ApiError('UNKNOWN_ACTION',404);
   const id=await actor(request,env);const input=data.data&&typeof data.data==='object'?data.data as Record<string,unknown>:{};
   if(action==='approve'&&input.state==='APPROVED'){
    const me=await rpc(env,'impjo_api',{p_actor:id,p_action:'me',p_data:{}}) as unknown as {kind:string;state:string;roles:string[]};
    if(me.kind!=='STAFF'||me.state!=='APPROVED'||!me.roles.includes('ADMIN'))throw new ApiError('ACCESS_DENIED',403);
    const activeTargets=await sb(env,`/rest/v1/impjo_principals?id=eq.${encodeURIComponent(String(input.id||''))}&archived_at=is.null&select=id`) as unknown as {id:string}[];if(!activeTargets.length)throw new ApiError('NOT_FOUND',404);
    const targets=await sb(env,`/rest/v1/impjo_staff_identities?principal_id=eq.${encodeURIComponent(String(input.id||''))}&select=auth_user_id`) as unknown as {auth_user_id:string}[];
    if(targets[0]){
     if(!['ADMIN','OPERATOR'].includes(String(input.role))||input.id===id)throw new ApiError('ACCESS_DENIED',403);
     const authUser=await sb(env,'/auth/v1/admin/users/'+targets[0].auth_user_id) as unknown as {email_confirmed_at?:string;banned_until?:string};
     if(authUser.banned_until&&Date.parse(authUser.banned_until)>Date.now())throw new ApiError('ACCESS_DENIED',403);
     if(!authUser.email_confirmed_at){
      await sb(env,'/auth/v1/admin/users/'+targets[0].auth_user_id,{email_confirm:true},undefined,'PUT');
      await sb(env,'/rest/v1/impjo_events',{actor_id:id,action:'STAFF_EMAIL_ACTIVATED_BY_ADMIN',target_id:input.id});
     }
    }
   }
   const result=await rpc(env,'impjo_api',{p_actor:id,p_action:action,p_data:input});
   if(action==='approve')return json({...result,confirmed:await rpc(env,'impjo_account_admin',{p_actor:id,p_action:'confirmation',p_target:input.id})});
   return json(result);
  }
 }
 if(path==='me'&&request.method==='GET')return json(await rpc(env,'impjo_api',{p_actor:await actor(request,env),p_action:'me',p_data:{}}));
 return json({error:'NOT_FOUND'},404);
}catch(error){if(error instanceof ApiError)return json({error:error.message},error.status);return json({error:'SERVICE_UNAVAILABLE'},503)}}


