export type GmailConfig={DOCUMENT_FROM_EMAIL?:string;GMAIL_APP_PASSWORD?:string};
export type DocumentMail={to:string;jobNumber:string;blNumber:string;contact:string;documentId:string;pdfBase64?:string;status?:string;issueDetail?:string;reporter?:string;destination?:string;hbl?:string;consignee?:string;jobDate?:string};
type Transport={sendMail:(mail:Record<string,unknown>)=>Promise<{accepted?:unknown[];messageId?:string;serverMessageId?:string}>;close:()=>void};
export type TransportFactory=(options:Record<string,unknown>)=>Transport;
export function gmailConfigured(env:GmailConfig){return /^[A-Za-z0-9._%+-]+@gmail\.com$/i.test(env.DOCUMENT_FROM_EMAIL||'')&&/^[a-z]{16}$/i.test((env.GMAIL_APP_PASSWORD||'').replace(/\s/g,''))}
export async function sendGmailDocument(env:GmailConfig,mail:DocumentMail,createTransport:TransportFactory){
 if(!gmailConfigured(env))throw Error('EMAIL_NOT_CONFIGURED');
 if(!/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(mail.to)||/[\r\n]/.test(mail.to)||!/^[0-9a-f-]{36}$/.test(mail.documentId))throw Error('INVALID_DOCUMENT');
 const hasPdf=!!mail.pdfBase64;
 if(!hasPdf&&!['COMPLETED','ISSUE_REPORTED'].includes(mail.status||''))throw Error('INVALID_STATUS_REPORT');
 if(mail.status==='ISSUE_REPORTED'&&!mail.issueDetail?.trim())throw Error('INVALID_STATUS_REPORT');
 const labels:Record<string,string>={COMPLETED:'เสร็จสมบูรณ์',ISSUE_REPORTED:'ไม่สมบูรณ์ — พบปัญหา',IN_PROGRESS:'กำลังดำเนินการ',PENDING_HANDOVER:'รอส่งมอบ'};
 const report=mail.status?'\nผลการดำเนินงาน: '+(labels[mail.status]||mail.status)+(mail.status==='ISSUE_REPORTED'?'\nสาเหตุ: '+mail.issueDetail:''):'',details=(mail.jobDate?'\nวันที่งาน: '+mail.jobDate:'')+(mail.destination?'\nDestination: '+mail.destination:'')+(mail.hbl?'\nHBL Number: '+mail.hbl:'')+(mail.consignee?'\nConsignee: '+mail.consignee:'')+(mail.reporter?'\nผู้รายงาน: '+mail.reporter:'');
 const transport=createTransport({host:'smtp.gmail.com',port:465,secure:true,tls:{rejectUnauthorized:true,minVersion:'TLSv1.2'},auth:{user:env.DOCUMENT_FROM_EMAIL,pass:env.GMAIL_APP_PASSWORD!.replace(/\s/g,'')},connectionTimeout:8000,greetingTimeout:5000,socketTimeout:10000,dnsTimeout:5000,logger:false,debug:false,disableFileAccess:true,disableUrlAccess:true});
 try{
  const result=await transport.sendMail({from:{name:'IMP Job Order',address:env.DOCUMENT_FROM_EMAIL},to:mail.to,subject:(hasPdf?'เอกสารส่งกลับ':'แจ้งผล '+labels[mail.status!])+' '+mail.jobNumber+' / B/L '+mail.blNumber,text:'เรียนเจ้าของงาน\n\n'+(hasPdf?'ได้รับเอกสารส่งกลับจาก MESS แล้ว':'MESS ยืนยันผลการดำเนินงานแล้ว')+'\nJob Order: '+mail.jobNumber+'\nB/L: '+mail.blNumber+'\nContact Name: '+mail.contact+details+report+'\n\n'+(hasPdf?'กรุณาตรวจสอบเอกสาร PDF ที่แนบมาพร้อมอีเมลนี้':'หากมีเอกสารส่งกลับ MESS จะตรวจสอบและยืนยันส่ง PDF แยกภายหลัง')+'\n\nIMP Job Order',messageId:'<imp-'+(hasPdf?'document':'status')+'-'+mail.documentId+'@gmail.com>',...(hasPdf?{attachments:[{filename:'IMP-'+mail.documentId+'.pdf',content:mail.pdfBase64,encoding:'base64',contentType:'application/pdf'}]}:{})});
  if(!result.accepted?.some(x=>typeof x==='string'&&x.toLowerCase()===mail.to.toLowerCase()))throw Error('EMAIL_PROVIDER_REJECTED');
  return{state:'ACCEPTED' as const,providerId:result.serverMessageId||result.messageId||'smtp-accepted'};
 }catch(error){const e=error as {code?:string;responseCode?:number;message?:string};if(e.code==='EAUTH'||(e.responseCode&&e.responseCode>=500)||e.message==='EMAIL_PROVIDER_REJECTED')throw Error('EMAIL_PROVIDER_REJECTED');throw Error('DELIVERY_UNCONFIRMED')}
 finally{transport.close()}
}
