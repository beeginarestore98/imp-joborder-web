export function qrJobPath(value:string):string|null{
 try{const url=new URL(value);if(url.origin!=='https://imp-joborder-web.pages.dev'||url.username||url.password)return null;return /^\/jobs\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/?$/i.test(url.pathname)?url.pathname.replace(/\/$/,''):null}catch{return null}
}