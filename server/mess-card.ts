export type CardAction={type:string;label?:string;data?:string;text?:string;uri?:string};
export type WorkItem={jobNumber:string;blNumber:string;status:string;jobDate?:string|null;contact?:string;destination?:string;purpose?:string;amount?:number|null;action?:CardAction};
export type CardPresentation={role?:string;summary?:string;items?:WorkItem[];current?:WorkItem;nextStatus?:string};
type ChatMessage={type:string;text:string;quickReply?:{items:{action:unknown}[]};presentation?:CardPresentation};
const yellow='#FFCC00',black='#171717',red='#C71920',white='#FFFFFF',gray='#E7E7E2';
const labels:Record<string,string>={PENDING_HANDOVER:'รอส่งมอบ',IN_PROGRESS:'กำลังดำเนินการ',COMPLETED:'เสร็จสมบูรณ์',ISSUE_REPORTED:'แจ้งปัญหา'};
const text=(value:string,size='sm',color=black)=>({type:'text',text:value||'—',size,color,wrap:true});
export function workProgress(status:string){
 const step=status==='COMPLETED'?3:status==='IN_PROGRESS'||status==='ISSUE_REPORTED'?2:status==='PENDING_HANDOVER'?1:0;
 return{type:'box',layout:'vertical',spacing:'sm',margin:'lg',contents:[
  {...text('ขั้นตอนการดำเนินงาน','xs','#666666'),weight:'bold'},
  {type:'box',layout:'horizontal',spacing:'sm',contents:['รอส่งมอบ','ดำเนินการ','เสร็จสิ้น'].map((label,i)=>({type:'box',layout:'vertical',flex:1,spacing:'sm',contents:[
   {type:'box',layout:'vertical',height:'7px',backgroundColor:status==='ISSUE_REPORTED'&&i===1?red:i<step?yellow:gray,cornerRadius:'4px',contents:[]},
   {...text(label,'xxs',i<step?black:'#777777'),align:'center'}
  ]}))},
  text(status==='ISSUE_REPORTED'?'มีประเด็นที่ต้องดำเนินการแก้ไข ยังไม่ถือว่างานเสร็จสมบูรณ์':step?`สถานะปัจจุบัน: ${labels[status]}`:'ไม่พบข้อมูลสถานะล่าสุด','xs',status==='ISSUE_REPORTED'?red:'#555555')
 ]};
}
function actionButton(action:CardAction){
 const danger=action.label?.includes('ยืนยัน')||action.label?.includes('ปัญหา');
 // Box actions permit a readable black label on yellow, unlike primary buttons.
 return{type:'box',layout:'vertical',backgroundColor:danger?red:yellow,paddingAll:'12px',cornerRadius:'8px',action:{...action,label:(action.label||'ดูรายละเอียด').slice(0,20)},contents:[{...text(action.label||'ดูรายละเอียด','sm',danger?white:black),align:'center',weight:'bold'}]};
}
function bubble(heading:string,body:unknown[],actions:CardAction[],role:string){
 return{type:'bubble',size:'mega',header:{type:'box',layout:'vertical',backgroundColor:yellow,paddingAll:'18px',spacing:'sm',contents:[
  {...text('IMP · '+role,'xs'),weight:'bold'},{...text(heading,'lg'),weight:'bold'}
 ]},body:{type:'box',layout:'vertical',backgroundColor:white,paddingAll:'18px',spacing:'md',contents:body},...(actions.length?{footer:{type:'box',layout:'vertical',backgroundColor:white,spacing:'sm',paddingAll:'16px',contents:actions.map(actionButton)}}:{})};
}
function itemBody(item:WorkItem){return[
 {...text(item.jobNumber,'sm','#6B5700'),weight:'bold'},text('B/L','xs','#666666'),{...text(item.blNumber,'lg'),weight:'bold'},
 ...(item.jobDate?[text('วันที่งาน: '+formatDate(item.jobDate),'xs','#666666')]:[]),
 ...(item.contact?[text('Contact Name: '+item.contact,'sm')]:[]),
 ...(item.destination?[text('Destination: '+item.destination,'sm')]:[]),
 ...(item.purpose?[text('วัตถุประสงค์: '+item.purpose,'sm')]:[]),
 ...(item.amount!=null?[text('ยอดเงิน: '+Number(item.amount).toLocaleString('th-TH')+' บาท','sm')]:[]),
 {type:'box',layout:'vertical',backgroundColor:item.status==='ISSUE_REPORTED'?'#FFF0F0':item.status==='COMPLETED'?black:'#FFF6CE',paddingAll:'10px',cornerRadius:'6px',contents:[{...text(labels[item.status]||'ไม่ทราบสถานะ','sm',item.status==='ISSUE_REPORTED'?red:item.status==='COMPLETED'?white:black),weight:'bold'}]},
 workProgress(item.status)
]}
function formatDate(value:string){return /^\d{4}-\d{2}-\d{2}$/.test(value)?value.slice(8,10)+'/'+value.slice(5,7)+'/'+value.slice(0,4):value}
export function messCard(message:ChatMessage,fallbackRole='MESS'){
 const[heading,...lines]=message.text.split('\n'),presentation=message.presentation,role=presentation?.role||fallbackRole;
 const actions=message.quickReply?.items.map(i=>i.action).filter((a):a is CardAction=>!!a&&typeof a==='object'&&'type'in a&&typeof a.type==='string'&&['postback','message','uri'].includes(a.type))||[];
 const base={type:'flex',altText:message.text.slice(0,400)||'IMP Job Order'};
 if(presentation?.items?.length){
  const items=presentation.items.slice(0,10);
  const keys=new Set(items.map(i=>i.action?.data||i.action?.text||i.action?.uri).filter(Boolean));
  const navigation=actions.filter(a=>!keys.has(a.data||a.text||a.uri));
  const cards=items.map(i=>bubble('ความคืบหน้างาน',itemBody(i),i.action?[{...i.action,label:'ดูรายละเอียด / อัปเดต'}]:[],role));
  if(navigation.length)cards.push(bubble('รายการงานเพิ่มเติม',[text(presentation.summary||heading||'รายการงาน'),text('เลื่อนการ์ดเพื่อดูแต่ละ B/L หรือเลือกเมนูด้านล่าง','sm','#666666')],navigation,role));
  return{...base,contents:cards.length===1?cards[0]:{type:'carousel',contents:cards}};
 }
 const body:unknown[]=[text(lines.join('\n').trim()||'กรุณาเลือกดำเนินการจากเมนูด้านล่าง')];
 if(presentation?.current){
  body.push(workProgress(presentation.current.status));
  if(presentation.nextStatus)body.push({type:'box',layout:'vertical',backgroundColor:'#FFF6CE',paddingAll:'12px',cornerRadius:'6px',contents:[text('สถานะที่จะบันทึก: '+(labels[presentation.nextStatus]||'—'),'sm'),text('ระบบจะเปลี่ยนสถานะเมื่อท่านยืนยันบันทึกเท่านั้น','xs','#666666')]});
 }
 return{...base,contents:bubble(heading||'ข้อมูลการปฏิบัติงาน',body,actions,role)};
}
