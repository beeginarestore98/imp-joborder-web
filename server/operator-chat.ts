import type{CardAction,CardPresentation}from'./mess-card.ts';
type Result={total:number;page:number;key:string;contact:string;draft:string|number;selected:string[];contacts:{key:string;contact:string;bl_count:number}[];bls:{id:string;number:string;job_number:string;job_date:string|null;destination:string;purpose:string;amount:number|null;status:string}[];purpose_summary:{purpose:string;jobs:number;amount:number|null}[];items:{number:string;job_number:string;status:string}[];status:string;issue:string;changed:number};
const statusLabels:Record<string,string>={PENDING_HANDOVER:'รอส่งมอบ',IN_PROGRESS:'กำลังดำเนินการ',COMPLETED:'เสร็จสมบูรณ์',ISSUE_REPORTED:'แจ้งปัญหา'};
const button=(label:string,data:string):CardAction=>({type:'postback',label:label.slice(0,20),data});
const back:CardAction={type:'message',label:'เลือกผู้ประสานงาน',text:'OPERATOR'};
const chat=(text:string,actions:CardAction[],presentation?:CardPresentation)=>({type:'text',text,quickReply:{items:actions.map(action=>({action}))},...(presentation?{presentation}:{})});
export async function operatorBrowse(postback:string,call:(action:string,data?:unknown)=>Promise<unknown>){
 const invoke=async(action:string,data:unknown={})=>await call(action,data) as Result;
 const contacts=postback.match(/^op-contacts:OPERATOR:(\d+)$/);
 const contact=postback.match(/^op-contact:OPERATOR:([0-9a-f]{32}):(\d+)$/);
 const start=postback.match(/^op-start:OPERATOR:([0-9a-f]{32}):(\d+)$/);
 const toggle=postback.match(/^op-toggle:OPERATOR:(\d+):([0-9a-f-]{36})$/);
 const page=postback.match(/^op-page:OPERATOR:(\d+):(\d+)$/);
 const choose=postback.match(/^op-status:OPERATOR:(\d+):(PENDING_HANDOVER|IN_PROGRESS|COMPLETED|ISSUE_REPORTED)$/);
 const issue=postback.match(/^op-issue:OPERATOR:(\d+):(RESCHEDULE|DOCUMENT)$/);
 const confirm=postback.match(/^op-confirm:OPERATOR:(\d+)$/);
 if(confirm){const r=await invoke('confirm',{draft:confirm[1]});return chat('บันทึกสถานะสำเร็จ\n\nเปลี่ยนสถานะ '+r.changed+' จาก '+r.total+' B/L\nสถานะ: '+statusLabels[r.status]+'\n\n'+r.items.map(i=>i.job_number+' · '+i.number).join('\n')+'\n\nข้อมูลบนเว็บและประวัติการดำเนินงานได้รับการอัปเดตแล้ว',[back]);}
 if(choose?.[2]==='ISSUE_REPORTED')return chat('ระบุปัญหาสำหรับรายการที่เลือก\n\nปัญหานี้จะใช้กับทุก B/L ในชุด กรุณาเลือกประเภทปัญหา ก่อนตรวจสอบและยืนยัน',[button('แจ้งวันนัดใหม่','op-issue:OPERATOR:'+choose[1]+':RESCHEDULE'),button('แก้ไขเอกสาร','op-issue:OPERATOR:'+choose[1]+':DOCUMENT'),back]);
 if(choose||issue){const r=await invoke('propose',{draft:choose?.[1]||issue?.[1],status:choose?.[2]||'ISSUE_REPORTED',issue:issue?(issue[2]==='RESCHEDULE'?'แจ้งวันนัดใหม่':'แก้ไขเอกสาร'):''});return chat('ตรวจสอบก่อนยืนยันทั้งชุด\n\nทั้งหมด '+r.items.length+' B/L\nสถานะใหม่: '+statusLabels[r.status]+(r.issue?'\nรายละเอียดปัญหา: '+r.issue:'')+'\n\n'+r.items.map(i=>i.job_number+' · '+i.number+'\n'+statusLabels[i.status]+' → '+statusLabels[r.status]).join('\n\n')+'\n\nยังไม่บันทึกจนกดยืนยัน ภายใน 10 นาที\nหากรายการใดเปลี่ยนสถานะ ระบบจะไม่บันทึกทั้งชุด',[button('ยืนยันบันทึกทั้งชุด','op-confirm:OPERATOR:'+r.draft),back]);}
 if(!postback||contacts){const r=await invoke('contacts',{page:Number(contacts?.[1]||1)});return chat('OPERATOR · เลือกผู้ประสานงาน\n\nเรียงตาม Contact Name · '+r.total+' รายชื่อ\n'+(r.contacts.length?r.contacts.map(c=>(c.contact||'ไม่ระบุชื่อ')+' · '+c.bl_count+' B/L').join('\n'):'ไม่พบงานในระบบ')+'\n\nเลือกชื่อเพื่อดู Destination, B/L และวัตถุประสงค์',[...r.contacts.map(c=>button(c.contact||'ไม่ระบุชื่อ','op-contact:OPERATOR:'+c.key+':1')),...(r.page>1?[button('หน้าก่อน','op-contacts:OPERATOR:'+(r.page-1))]:[]),...(r.page*10<r.total?[button('หน้าถัดไป','op-contacts:OPERATOR:'+(r.page+1))]:[]),{type:'uri',label:'สร้าง Job Order',uri:'https://imp-joborder-web.pages.dev/operator'}]);}
 if(!(contact||start||toggle||page))return chat('คำสั่งไม่ถูกต้อง กรุณาเลือกผู้ประสานงานใหม่',[back]);
 const r=await invoke(toggle?'toggle':page?'page':start?'start':'bls',toggle?{draft:toggle[1],bl_id:toggle[2]}:page?{draft:page[1],page:Number(page[2])}:{key:(contact||start)![1],page:Number((contact||start)![2])});
 const multi=!!(start||toggle||page),selected=r.selected||[];
 const actions:CardAction[]=multi?r.bls.map(b=>button((selected.includes(b.id)?'✓ ':'□ ')+b.number,'op-toggle:OPERATOR:'+r.draft+':'+b.id)):r.bls.map(b=>button(b.number,'handover-select:OPERATOR:'+b.id));
 if(r.page>1)actions.push(button('หน้าก่อน',multi?'op-page:OPERATOR:'+r.draft+':'+(r.page-1):'op-contact:OPERATOR:'+r.key+':'+(r.page-1)));
 if(r.page*5<r.total)actions.push(button('หน้าถัดไป',multi?'op-page:OPERATOR:'+r.draft+':'+(r.page+1):'op-contact:OPERATOR:'+r.key+':'+(r.page+1)));
 if(multi&&selected.length)for(const [status,label]of Object.entries(statusLabels))actions.push(button(label,'op-status:OPERATOR:'+r.draft+':'+status));
 if(!multi&&r.total)actions.push(button('เลือกหลาย B/L','op-start:OPERATOR:'+r.key+':'+r.page));
 actions.push(back);
 const text='Contact Name: '+(r.contact||'ไม่พบงาน')+'\nทั้งหมด '+r.total+' B/L · หน้า '+r.page+'\n\nวัตถุประสงค์รวม (นับตาม Job)\n'+r.purpose_summary.map(s=>'• '+s.purpose+' · '+s.jobs+' งาน'+(s.amount!=null?' · '+Number(s.amount).toLocaleString('th-TH')+' บาท':'')).join('\n')+(multi?'\n\nเลือกแล้ว '+selected.length+'/20 รายการ\nกด □ เพื่อเลือก หรือ ✓ เพื่อเอาออก แล้วเลือกสถานะด้านล่าง':'\n\nเลือก B/L เพื่อดูรายละเอียด หรือเลือกหลายรายการ');
 return chat(text,actions,multi?undefined:{role:'OPERATOR',summary:text,items:r.bls.map((b,i)=>({jobNumber:b.job_number,blNumber:b.number,status:b.status,jobDate:b.job_date,contact:r.contact,destination:b.destination,purpose:b.purpose,amount:b.amount,action:actions[i]}))});
}
