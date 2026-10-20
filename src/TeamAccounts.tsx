import {useEffect,useState} from 'react';
type Call=(name:string,data?:unknown)=>Promise<any>;
type LinkRow={id:string;state:string;line_name:string;staff_name?:string;staff_id?:string;line_id?:string};
export function TeamLineLink({call,allowed}:{call:Call;allowed:boolean}){
 const[links,setLinks]=useState<LinkRow[]>([]),[code,setCode]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const load=()=>call('line_link_mine').then(setLinks).catch(e=>setError(e.message));
 useEffect(()=>{void load()},[]);
 useEffect(()=>{if(!code)return;const timer=setTimeout(()=>setCode(''),600000);return()=>clearTimeout(timer)},[code]);
 return <section className="panel form-panel"><h2>ผูกบัญชี LINE สำหรับ OPERATOR</h2><p>เข้าสู่ LINE Portal ด้วยบัญชี LINE ของคุณก่อน จากนั้นกลับมาใช้บัญชีอีเมลทีมงานเพื่อสร้างรหัสผูก</p><ol><li>สร้างรหัสผูกด้านล่าง รหัสใช้ได้ครั้งเดียวภายใน 10 นาที</li><li>คัดลอกข้อความทั้งหมดไปส่งในแชตส่วนตัว OA @110deiyl</li><li>รอ ADMIN ตรวจสอบและอนุมัติการผูกในหน้า “ผู้ใช้และสิทธิ์”</li><li>พิมพ์ OPERATOR ในแชต เพื่อเลือก B/L และยืนยันส่งมอบ</li></ol>{links.map(l=><p className="notice" key={l.id}>LINE: {l.line_name} · {l.state==='APPROVED'?'อนุมัติแล้ว':'รอ ADMIN อนุมัติ'}</p>)}{error&&<p className="error" role="alert">{error}</p>}{allowed&&!links.length&&<button className="primary" disabled={busy} onClick={async()=>{setBusy(true);setError('');try{const r=await call('line_link_create_code');setCode(r.code)}catch(e){setError((e as Error).message)}finally{setBusy(false)}}}>สร้างรหัสผูก LINE</button>}{!allowed&&<p>เฉพาะบัญชีทีมงานบทบาท OPERATOR ที่ได้รับอนุมัติเท่านั้นที่ผูกเพื่อส่งมอบงานในแชตได้</p>}{code&&<label>ข้อความสำหรับส่งให้ OA (เก็บเป็นส่วนตัว)<textarea readOnly rows={3} value={'ผูกบัญชี '+code}/></label>}<button className="secondary" onClick={()=>void load()}>ตรวจสอบสถานะการผูก</button><p><a className="text-link" href="https://line.me/R/ti/p/@110deiyl" target="_blank" rel="noreferrer">เปิด OA JOBORDER-IMP-DHL</a></p></section>
}
export function AdminTeamLinks({call}:{call:Call}){
 const[links,setLinks]=useState<LinkRow[]>([]),[error,setError]=useState('');
 const load=()=>call('line_link_list').then(setLinks).catch(e=>setError(e.message));
 useEffect(()=>{void load()},[]);
 return <section className="panel form-panel"><h2>อนุมัติการผูก LINE กับ OPERATOR</h2><p>ตรวจสอบเจ้าของทั้งบัญชีทีมงานและบัญชี LINE ก่อนอนุมัติ การพิมพ์ OPERATOR ในแชตไม่ให้สิทธิ์เอง</p>{error&&<p role="alert" className="error">{error}</p>}{!links.length&&<p>ยังไม่มีคำขอผูกบัญชี</p>}{links.map(l=><LinkApproval key={l.id} row={l} call={call} reload={load}/>)}<button className="secondary" onClick={()=>void load()}>โหลดคำขอใหม่</button></section>
}
function LinkApproval({row:l,call,reload}:{row:LinkRow;call:Call;reload:()=>unknown}){
 const[confirmed,setConfirmed]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function save(action:string){setBusy(true);setError('');try{await call(action,{id:l.id});reload()}catch(e){setError((e as Error).message)}finally{setBusy(false)}}
 return <article className="bl-card"><h3>{l.staff_name}</h3><p>LINE: {l.line_name} · {l.state==='APPROVED'?'อนุมัติแล้ว':'รออนุมัติ'}</p><p className="footnote">ทีมงาน: {l.staff_id}<br/>LINE: {l.line_id}</p>{l.state==='PENDING'&&<><label className="checkbox"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/>ตรวจสอบเจ้าของทั้งสองบัญชีแล้ว</label><button className="primary" disabled={!confirmed||busy} onClick={()=>void save('line_link_approve')}>อนุมัติการผูก</button></>}<button className="secondary" disabled={busy} onClick={()=>void save('line_link_revoke')}>ถอนการผูก / ปฏิเสธ</button>{error&&<p className="error" role="alert">{error}</p>}</article>
}
