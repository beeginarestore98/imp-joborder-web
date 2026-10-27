export type GmailConfig={DOCUMENT_FROM_EMAIL?:string;GMAIL_APP_PASSWORD?:string};
export type DocumentMail={to:string;jobNumber:string;blNumber:string;contact:string;documentId:string;pdfBase64:string};
type Transport={sendMail:(mail:Record<string,unknown>)=>Promise<{accepted?:unknown[];messageId?:string;serverMessageId?:string}>;close:()=>void};
export type TransportFactory=(options:Record<string,unknown>)=>Transport;
export function gmailConfigured(env:GmailConfig){return /^[A-Za-z0-9._%+-]+@gmail\.com$/i.test(env.DOCUMENT_FROM_EMAIL||'')&&/^[a-z]{16}$/i.test((env.GMAIL_APP_PASSWORD||'').replace(/\s/g,''))}
export async function sendGmailDocument(env:GmailConfig,mail:DocumentMail,createTransport:TransportFactory){
 if(!gmailConfigured(env))throw Error('EMAIL_NOT_CONFIGURED');
 if(!/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(mail.to)||/[\r\n]/.test(mail.to)||!/^[0-9a-f-]{36}$/.test(mail.documentId))throw Error('INVALID_DOCUMENT');
 const transport=createTransport({host:'smtp.gmail.com',port:465,secure:true,tls:{rejectUnauthorized:true,minVersion:'TLSv1.2'},auth:{user:env.DOCUMENT_FROM_EMAIL,pass:env.GMAIL_APP_PASSWORD!.replace(/\s/g,'')},connectionTimeout:8000,greetingTimeout:5000,socketTimeout:10000,dnsTimeout:5000,logger:false,debug:false,disableFileAccess:true,disableUrlAccess:true});
 try{
  const result=await transport.sendMail({from:{name:'IMP Job Order',address:env.DOCUMENT_FROM_EMAIL},to:mail.to,subject:'เอกสารส่งกลับ '+mail.jobNumber+' / B/L '+mail.blNumber,text:'เรียนเจ้าของงาน\n\nได้รับเอกสารส่งกลับจาก MESS แล้ว\nJob Order: '+mail.jobNumber+'\nB/L: '+mail.blNumber+'\nContact Name: '+mail.contact+'\n\nกรุณาตรวจสอบเอกสาร PDF ที่แนบมาพร้อมอีเมลนี้\n\nIMP Job Order',messageId:'<imp-document-'+mail.documentId+'@gmail.com>',attachments:[{filename:'IMP-'+mail.documentId+'.pdf',content:mail.pdfBase64,encoding:'base64',contentType:'application/pdf'}]});
  if(!result.accepted?.some(x=>typeof x==='string'&&x.toLowerCase()===mail.to.toLowerCase()))throw Error('EMAIL_PROVIDER_REJECTED');
  return{state:'ACCEPTED' as const,providerId:result.serverMessageId||result.messageId||'smtp-accepted'};
 }catch(error){const e=error as {code?:string;responseCode?:number;message?:string};if(e.code==='EAUTH'||(e.responseCode&&e.responseCode>=500)||e.message==='EMAIL_PROVIDER_REJECTED')throw Error('EMAIL_PROVIDER_REJECTED');throw Error('DELIVERY_UNCONFIRMED')}
 finally{transport.close()}
}
