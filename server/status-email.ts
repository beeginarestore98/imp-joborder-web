import {gmailConfigured,type DocumentMail} from './gmail-mailer.ts';
import {storedFile,base64,type DocumentEnv} from './documents.ts';
type Env=DocumentEnv;
export async function deliverStatusEmail(env:Env,id:string,call:(action:string,data:unknown)=>Promise<any>){
 if(!gmailConfigured(env)||!env.sendDocumentMail)return {state:'NOT_CONFIGURED'};
 const claim=await call('claim',{id});if(claim.skip)return {state:claim.state};
 let state='UNKNOWN',provider_id='',error='DELIVERY_UNCONFIRMED';
 let attachmentReady=true;if(claim.document_path){try{claim.pdfBase64=base64(await storedFile(env,claim.document_path))}catch{attachmentReady=false;state='FAILED';error='DOCUMENT_STORAGE_FAILED'}}
 try{if(!attachmentReady)throw Error('DOCUMENT_STORAGE_FAILED');const result=await env.sendDocumentMail(claim as DocumentMail);state=result.state;provider_id=result.providerId;error=''}catch(e){if((e as Error).message==='EMAIL_PROVIDER_REJECTED'){state='FAILED';error='EMAIL_PROVIDER_REJECTED'}}
 try{await call('finish',{id,lease:claim.lease,state,provider_id,error})}catch{return {state:'UNKNOWN'}}
 return {state};
}
export function statusEmailText(result?:{state?:string}){if(!result)return '';const text:Record<string,string>={ACCEPTED:'อีเมลแจ้งผล: ระบบอีเมลรับข้อความแล้ว',NO_RECIPIENT:'อีเมลแจ้งผล: ยังไม่ส่ง — กรุณาให้ ADMIN ตั้งอีเมลผู้รับตาม Contact Name',NOT_CONFIGURED:'อีเมลแจ้งผล: ยังไม่ส่ง — บริการอีเมลยังไม่พร้อม',RECIPIENT_CHANGED:'อีเมลแจ้งผล: ยังไม่ส่ง — การตั้งค่าผู้รับเปลี่ยน กรุณาติดต่อ ADMIN',FAILED:'อีเมลแจ้งผล: ส่งไม่สำเร็จ กรุณาติดต่อ ADMIN',UNKNOWN:'อีเมลแจ้งผล: ยังยืนยันผลไม่ได้ กรุณาให้ ADMIN ตรวจสอบก่อนส่งซ้ำ',SENDING:'อีเมลแจ้งผล: กำลังส่ง',ERROR:'อีเมลแจ้งผล: ยังยืนยันผลไม่ได้ กรุณาติดต่อ ADMIN'};return '\n\n'+(text[result.state||'']||'อีเมลแจ้งผล: รอดำเนินการ')}
