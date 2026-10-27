export const phonePattern='[+]?[0-9](?:[0-9]| |\\(|\\)|\\.|-|#|x|X){5,29}';
export function validContactPhone(value:string){const phone=value.trim(),digits=phone.replace(/[^0-9]/g,'');return new RegExp('^'+phonePattern+'$').test(phone)&&digits.length>=6&&digits.length<=20}
