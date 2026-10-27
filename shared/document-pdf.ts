export const MAX_DOCUMENT_PAGES=10,MAX_DOCUMENT_BYTES=5*1024*1024;
export function jpegSize(bytes:Uint8Array){
 if(bytes[0]!==255||bytes[1]!==216||bytes.at(-2)!==255||bytes.at(-1)!==217)throw Error('INVALID_DOCUMENT_IMAGE');
 let i=2;
 while(i+8<bytes.length){if(bytes[i++]!==255)throw Error('INVALID_DOCUMENT_IMAGE');while(bytes[i]===255)i++;const marker=bytes[i++];if(marker===218||marker===217)break;const length=(bytes[i]<<8)|bytes[i+1];if(length<2||i+length>bytes.length)throw Error('INVALID_DOCUMENT_IMAGE');if(marker===192||marker===194){const height=(bytes[i+3]<<8)|bytes[i+4],width=(bytes[i+5]<<8)|bytes[i+6];if(bytes[i+2]!==8||bytes[i+7]!==3||width<1||height<1||width>2400||height>2400)throw Error('INVALID_DOCUMENT_IMAGE');return{width,height}}i+=length;
 }throw Error('INVALID_DOCUMENT_IMAGE');
}
export function imagesToPdf(pages:Uint8Array[]){
 if(!pages.length||pages.length>MAX_DOCUMENT_PAGES||pages.reduce((n,p)=>n+p.length,0)>MAX_DOCUMENT_BYTES)throw Error('DOCUMENT_LIMIT');
 const encoder=new TextEncoder(),chunks:Uint8Array[]=[],offsets:number[]=[0];let length=0;
 const write=(value:string|Uint8Array)=>{const bytes=typeof value==='string'?encoder.encode(value):value;chunks.push(bytes);length+=bytes.length};
 const object=(id:number,body:()=>void)=>{offsets[id]=length;write(id+' 0 obj\n');body();write('\nendobj\n')};
 write('%PDF-1.4\n%IMP scanned document\n');object(1,()=>write('<< /Type /Catalog /Pages 2 0 R >>'));
 object(2,()=>write('<< /Type /Pages /Count '+pages.length+' /Kids ['+pages.map((_,i)=>(3+i*3)+' 0 R').join(' ')+'] >>'));
 pages.forEach((image,i)=>{const{width,height}=jpegSize(image),id=3+i*3;const landscape=width>height,pw=landscape?842:595,ph=landscape?595:842,scale=Math.min((pw-36)/width,(ph-36)/height),w=width*scale,h=height*scale;
  object(id,()=>write('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 '+pw+' '+ph+'] /Resources << /XObject << /Image '+(id+1)+' 0 R >> >> /Contents '+(id+2)+' 0 R >>'));
  object(id+1,()=>{write('<< /Type /XObject /Subtype /Image /Width '+width+' /Height '+height+' /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length '+image.length+' >>\nstream\n');write(image);write('\nendstream')});
  const content='q\n'+w.toFixed(3)+' 0 0 '+h.toFixed(3)+' '+((pw-w)/2).toFixed(3)+' '+((ph-h)/2).toFixed(3)+' cm\n/Image Do\nQ\n';object(id+2,()=>write('<< /Length '+encoder.encode(content).length+' >>\nstream\n'+content+'endstream'));
 });
 const start=length;write('xref\n0 '+offsets.length+'\n0000000000 65535 f \n');for(const offset of offsets.slice(1))write(String(offset).padStart(10,'0')+' 00000 n \n');write('trailer\n<< /Size '+offsets.length+' /Root 1 0 R >>\nstartxref\n'+start+'\n%%EOF\n');
 const pdf=new Uint8Array(length);let cursor=0;for(const c of chunks){pdf.set(c,cursor);cursor+=c.length}return pdf;
}
