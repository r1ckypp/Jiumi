import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('../../',import.meta.url));
const tmp=mkdtempSync(join(tmpdir(),'jiumi-module-'));
try{
  const wasm=join(tmp,'timer.wasm');
  execFileSync(process.execPath,[join(root,'node_modules/assemblyscript/bin/asc.js'),join(root,'examples/focus-timer/index.ts'),'--runtime','stub','-O','--noExportMemory','--maximumMemory','1','-o',wasm]);
  const bytes=readFileSync(wasm);
  const manifest={
    id:'focus-timer',name:'专注计时',api:1,version:1,
    events:['host.ready','agent.started','host.tick','host.resume'],
    capabilities:['state','motion'],sha256:createHash('sha256').update(bytes).digest('hex'),wasm:bytes.toString('base64')
  };
  writeFileSync(join(root,'examples/modules/focus-timer.json'),JSON.stringify(manifest,null,2)+'\n');
}finally{rmSync(tmp,{recursive:true,force:true});}
