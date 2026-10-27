export function splitPurposes(value:string){return [...new Set(value.split('\n').map(x=>x.trim()).filter(Boolean))]}
export function joinPurposes(values:string[]){const result=[...new Set(values.map(x=>x.trim()).filter(Boolean))].join('\n');if(result.length>250)throw Error('วัตถุประสงค์ที่เลือกรวมกันต้องไม่เกิน 250 ตัวอักษร');return result}
