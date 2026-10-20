# จัดการงาน บัญชี Excel และรายงานเย็น

## สิทธิ์และการเก็บถาวร

- ADMIN แก้ไขชื่อ บทบาท สถานะ และเก็บบัญชีอื่นถาวรผ่านหน้า “ผู้ใช้และสิทธิ์” ได้ บัญชีตนเองเก็บถาวรไม่ได้
- บัญชีที่เก็บถาวรเป็น DISABLED พร้อมถอน Auth sessions, LINE sessions, การผูก LINE, รหัสผูก และ assignments
- กู้คืนบัญชีเป็น PENDING และไม่มี role เพื่อให้ ADMIN ตรวจสอบและอนุมัติใหม่ ประวัติเดิมเก็บไว้
- ADMIN / OPERATOR แก้ไข Job และรายละเอียด B/L, เพิ่ม B/L และเก็บ/กู้คืนทั้ง Job ได้ เลข Job และสถานะเดิมไม่เปลี่ยนจากการแก้ไข
- B/L เดิมไม่ถูกลบออกระหว่างแก้ไข เพื่อรักษาประวัติและการมอบหมาย งานที่เก็บถาวรไม่อยู่ในรายการปกติ การส่งมอบ หรือ Excel
- ใช้ updated_at ตรวจการแก้ไขพร้อมกัน หากข้อมูลเปลี่ยนหลังเปิดฟอร์มต้องโหลดใหม่ก่อนบันทึก

## Excel

หน้า Job Orders เลือกวันที่เริ่มต้น–สิ้นสุดตาม **Job Date** รวมทั้งสองวัน แล้วดาวน์โหลด `.xlsx` หนึ่งแถวต่อ B/L พร้อมข้อมูลติดต่อ สถานะ ปัญหา ผู้รับมอบหมาย และเวลาบันทึกตามเวลาไทย

รองรับสูงสุด 10,000 B/L ต่อครั้ง หากเกินจะแจ้งให้แบ่งช่วงวันที่ ไม่ตัดข้อมูลเงียบ ๆ งานที่ยังไม่มีวันที่และงานที่เก็บถาวรไม่รวมในไฟล์ ข้อความจากผู้ใช้บันทึกเป็น literal strings เพื่อไม่ให้ Excel รันสูตรที่แฝงมากับข้อมูล

## รายงาน LINE เวลา 17:00 น.

เริ่มต้น **ปิดการส่ง** และไม่มี mapping ผู้รับ ตามคำขอเจ้าของระบบ

1. ให้ Job OPR เข้าผ่าน LINE Portal และผ่านการอนุมัติ หรือผูก LINE กับบัญชี OPERATOR
2. ADMIN เปิดหน้า “รายงานเย็น LINE” จับคู่ Contact Name กับ LINE ผู้รับที่ถูกต้อง และเลือกเปิดรับรายงานราย Contact
3. ตรวจตัวอย่างรายงาน (ไม่ส่งข้อความ) แล้วเปิดการส่งอัตโนมัติ
4. ระบบจัดรายงานเฉพาะ Job Date ของวันนั้น เวลา 17:00 Asia/Bangkok ส่งแยกแชตส่วนตัวตาม Contact Name

แต่ละข้อความแสดงสถานะทุก B/L เสร็จสิ้น / กำลังดำเนินการ / รอส่งมอบ / มีปัญหา แบ่งหน้าละ 8 B/L ให้ครบทุกหน้า ผู้รับ MESS ที่อนุมัติแล้วดู B/L ทุกคนได้ตามเงื่อนไขใหม่ การรายงานผลยังจำกัดผู้รับมอบหมาย

ใช้ outbox, lease และ LINE retry key ป้องกันคำขอซ้ำ ตรวจผู้รับซ้ำก่อน push และเก็บสถานะ LINE รับคำขอ/ส่งไม่สำเร็จไว้ในเว็บ การรับคำขอจาก LINE ไม่ใช่การยืนยันว่าผู้รับเปิดอ่าน เมื่อปิดการส่งหรือเปลี่ยนผู้รับจะยกเลิกข้อความที่ยังค้างส่ง เก็บงานถาวรจะยกเลิกหน้ารายงานค้างที่มีงานนั้น

## Backend / Secrets

เรียง migration: `management.sql`, `evening-reports.sql`, `report-schedule.sql`, `report-network-schema.sql`, `report-network-security.sql`, `report-signed-scheduler.sql` และ `mess-contact-browse.sql` หลัง migration เดิม ทั้งหมดนำไปใช้กับโปรเจกต์จริงแล้ว ห้ามรันซ้ำ

- `impjo-api`: gateway และ session authentication เดิม, management/report RPC เฉพาะ service_role
- `impjo-reports`: HMAC SHA-256 จาก Vault พร้อม nonce ใช้ครั้งเดียวและอายุ 120 วินาที ตรวจฝั่งฐานข้อมูลก่อน claim คิว ไม่มี endpoint ส่งรายงานเปิดสาธารณะ
- รายงานใช้ LINE_MESSAGING_CHANNEL_ACCESS_TOKEN ที่มีอยู่ใน Supabase Secrets; ไม่ต้องเพิ่ม secret ใน frontend
- scheduler credential สร้างภายในฐานข้อมูลและเก็บใน Supabase Vault ชื่อ `impjo_evening_report_scheduler` ไม่เก็บใน source
- pg_cron สร้างรายงาน `0 10 * * *` UTC = 17:00 ไทย และปลุก sender ทุกนาทีเฉพาะมีคิวที่เปิดใช้งาน

## Validation

Production build, 42 Node tests และ transactional management/report tests ผ่าน ทดสอบไฟล์ XLSX, การไม่รันสูตร, การแบ่งรายงานครบทุก B/L, authorization, optimistic locking, Auth session revocation, recovery, recipient isolation และ retry idempotency

ทดสอบ endpoint scheduler จริง: HMAC proof ที่ถูกต้องได้ 200 / processed=0 ขณะปิดการส่ง; ใช้ proof ซ้ำได้ 401 ไม่มีข้อความถูกส่งจริง และยังไม่ได้ทดสอบการรับรายงานใน LINE ปลายทาง เนื่องจากเจ้าของเลือกตั้งค่าผู้รับภายหลัง

## MESS เลือก Contact / OPERATOR ส่งมอบ

MESS → ปุ่ม Contact Name → ปุ่ม B/L ไม่ต้องพิมพ์เลขงาน รายชื่อแบ่งหน้าละ 10 Contact และรายการแบ่งหน้าละ 5 B/L ไม่มีการตัด B/L จาก Job ที่มีหลายใบ งานปัจจุบันคืองานวันนี้และงานค้างที่ยังไม่เสร็จตามเวลาไทย งานที่ไม่มีวันที่และงานเก็บถาวรไม่แสดง

MESS ที่อนุมัติแล้วอ่านงานทุกคนได้ ทั้งเว็บและแชต แต่ can_report และ RPC status ยังตรวจ assignment ทุกครั้ง

OPERATOR ส่งมอบผ่านแชตด้วยคำสั่ง OPERATOR → เลือก B/L → ยืนยันส่งมอบ หลังเจ้าของผูก LINE กับบัญชีอีเมลและ ADMIN อนุมัติเท่านั้น ปัจจุบันไม่มี approved link จึงยังรอเจ้าของส่งรหัสผ่าน OA; ห้ามสร้าง mapping แทนเจ้าของ

pg_net เป็น extension ที่จัดการโดยระบบ สิทธิ์ PUBLIC บางส่วนไม่สามารถถอนโดย postgres ได้ จึงไม่ใส่ static scheduler credential ใน HTTP queue ใช้ HMAC proof อายุสั้นและ nonce ที่รับได้ครั้งเดียวแทน ไม่มี secret ใน frontend หรือ repository

## อัปเดต: บัญชี LINE เป็น OPERATOR โดยตรง

ADMIN อนุมัติบัญชี LINE ที่ลงทะเบียนแล้วเป็น OPERATOR ได้ผ่านหน้า ผู้ใช้และสิทธิ์ โดยใช้ principal LINE เดิมและตรวจ webhook signature ทุกครั้ง ไม่ต้องอ้างว่าเป็นบัญชีอีเมลเดียวกันหรือสร้าง staff mapping แทนเจ้าของ บัญชีดังกล่าวดูงานและส่งมอบ PENDING_HANDOVER → IN_PROGRESS ผ่าน LINE/เว็บได้ การสร้างหรือแก้ไข Job ยังคงใช้ฟอร์มบัญชีอีเมลทีมงานตามขอบเขตเดิม ADMIN ยังคงเป็นบัญชีทีมงานอีเมล; การผูก LINE ไม่ยกระดับเป็น ADMIN อัตโนมัติ

Migration line-operator.sql และ transactional test tests/line-operator.sql ใช้งานแล้ว Node tests เพิ่มเป็น 43 tests บัญชี Test - B เปลี่ยนจาก MESS เป็น OPERATOR ตามคำสั่งเจ้าของ การอนุมัติใหม่ถอน sessions และ assignment ของบทบาทเดิมตามนโยบายเดิม ให้ ADMIN มอบหมาย MESS ผู้รับงานก่อนรายงานผล


