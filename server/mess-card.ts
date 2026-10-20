type Action={type:string;label?:string;data?:string;text?:string;uri?:string};
export function messCard(message:{type:string;text:string;quickReply?:{items:{action:unknown}[]}}){
 const[heading,...lines]=message.text.split('\n');
 const actions=message.quickReply?.items.map(i=>i.action).filter((a):a is Action=>!!a&&typeof a==='object'&&'type'in a&&typeof a.type==='string'&&['postback','message','uri'].includes(a.type))||[];
 return{type:'flex',altText:message.text.slice(0,400),contents:{type:'bubble',size:'mega',header:{type:'box',layout:'vertical',backgroundColor:'#FFCC00',paddingAll:'16px',contents:[{type:'text',text:'IMP · MESS',size:'xs',color:'#171717',weight:'bold'},{type:'text',text:heading||'ข้อมูลงาน',color:'#171717',size:'md',weight:'bold',wrap:true}]},body:{type:'box',layout:'vertical',paddingAll:'16px',contents:[{type:'text',text:lines.join('\n').trim()||'เลือกดำเนินการด้านล่าง',wrap:true,size:'sm',color:'#334155'}]},...(actions.length?{footer:{type:'box',layout:'vertical',spacing:'sm',paddingAll:'12px',contents:actions.map(a=>({type:'button',height:'sm',style:a.label?.includes('ยืนยัน')?'primary':'secondary',...(a.label?.includes('ยืนยัน')?{color:'#C71920'}:{}),action:{...a,label:(a.label||'เลือก').slice(0,20)}}))}}:{})}};
}

