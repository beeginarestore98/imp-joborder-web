# ไม่ต้องเลือกผู้รับงาน

ตามคำยืนยันเจ้าของระบบ เอาส่วนเลือกผู้รับงานและบันทึกการมอบหมายออกจาก Job Detail ทั้งหมด OUTSOURCE ที่ ADMIN อนุมัติแล้วและบัญชียังเปิดใช้งานสามารถอัปเดตทุกงานได้เหมือน OPERATOR รวมถึงเปิดงานที่เสร็จแล้วกลับมา โดยไม่ต้องมี assignment MESS รายงานผลร่วมกันตามกติกาก่อนหน้า

เว็บและ LINE ตรวจบัญชี/บทบาท/สถานะบัญชีปัจจุบันฝั่ง Server และบันทึกผู้กระทำจริงทุกครั้ง รายงานปัญหาต้องมีรายละเอียดและยังมีหน้ายืนยันก่อนบันทึก ไม่ลบประวัติ assignments เดิม ไม่เปลี่ยนข้อมูล/สถานะงานจริงระหว่างทดสอบ

ใช้ migration shared-outsource.sql หลัง shared-mess-reporting.sql และ form-catalog.sql ทดสอบ transactional tests/shared-outsource.sql พร้อม Node tests และ Production build เอกสารนี้แทนกติกา OUTSOURCE ต้องได้รับมอบหมายในเอกสารรุ่นเก่า ไม่มี secret/environment variable ใหม่

