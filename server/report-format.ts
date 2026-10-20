export type EveningRow={job_number:string;job_date:string;bl_number:string;status:string;issue_detail?:string};
export type EveningPayload={date:string;contact_name:string;page:number;pages:number;rows:EveningRow[];summary:{total:number;completed:number;issues:number;progress:number;pending:number}};
const clean=(s:unknown,max:number)=>String(s??'').replace(/\s+/g,' ').trim().slice(0,max);
export function formatEveningReport(p:EveningPayload){
 const labels:Record<string,string>={COMPLETED:'✅ เสร็จสิ้น',ISSUE_REPORTED:'⚠️ มีปัญหา',IN_PROGRESS:'🚚 กำลังดำเนินการ',PENDING_HANDOVER:'⏳ รอส่งมอบ'};
 const date=/^\d{4}-\d{2}-\d{2}$/.test(p.date)?p.date.split('-').reverse().join('/'):clean(p.date,20);
 return `สรุปงานประจำวัน · ${date}\nJob OPR: ${clean(p.contact_name,120)}\n\nเสร็จ ${p.summary.completed}/${p.summary.total} B/L\nกำลังดำเนินการ ${p.summary.progress} · รอส่งมอบ ${p.summary.pending} · มีปัญหา ${p.summary.issues}\n\n${p.rows.map((r,i)=>`${(p.page-1)*8+i+1}. ${clean(r.job_number,40)}\nB/L: ${clean(r.bl_number,200)}\n${labels[r.status]||'ไม่ทราบสถานะ'}${r.status==='ISSUE_REPORTED'&&r.issue_detail?'\nรายละเอียด: '+clean(r.issue_detail,120):''}`).join('\n\n')}\n\nหน้า ${p.page}/${p.pages} · เฉพาะวันที่งาน ${date}\nสถานะ ณ เวลาจัดทำรายงาน`;
}
