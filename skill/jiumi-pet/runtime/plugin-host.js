// Only this host function runs as JavaScript in the dedicated worker.
// Community modules receive numeric ABI arguments and the declared imports.
function pluginWorker(){
  let instance, writes, action;
  self.onmessage=async ({data})=>{
    try {
      if(data.bytes){
        const module=await WebAssembly.compile(data.bytes);
        const allowed=new Set(data.capabilities);
        const api={};
        if(allowed.has('state'))api.save=value=>{
          if(!Number.isSafeInteger(value))throw Error('状态超出整数范围');
          writes=value;
        };
        if(allowed.has('motion'))api.play=value=>{
          if(value!==1 && value!==2)throw Error('未知反馈');
          action=value;
        };
        instance=await WebAssembly.instantiate(module,{pet:api});
        if(typeof instance.exports.step!=='function')throw Error('缺少 step 入口');
        postMessage({ready:true});
      } else {
        writes=undefined;action=0;
        instance.exports.step(data.index,data.now,data.state);
        postMessage({writes,action,terminal:data.terminal});
      }
    } catch {postMessage({error:'插件执行失败'});}
  };
}

// Restrict v1 modules to scalar functions with no table or linear memory.
// Section boundaries are validated independently by the WebAssembly compiler.
async function verifyModule(m){
  if(!m || typeof m.id!=='string' || m.id==='constructor' || m.api!==1 || !/^[a-z][a-z0-9-]{0,47}$/.test(m.id) ||
     !Number.isSafeInteger(m.version)||m.version<1 || typeof m.name!=='string'||!m.name.length||m.name.length>80 ||
     !Array.isArray(m.events)||m.events.length>24||m.events.some(e=>typeof e!=='string'||!e.length||e.length>160) ||
     !Array.isArray(m.capabilities)||m.capabilities.length>2||m.capabilities.some(c=>!['state','motion'].includes(c)) ||
     typeof m.wasm!=='string'||m.wasm.length>90000)throw Error('插件格式或能力不兼容');
  const bytes=Uint8Array.from(atob(m.wasm),ch=>ch.charCodeAt(0));
  const digest=await crypto.subtle.digest('SHA-256',bytes);
  if(Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('')!==m.sha256)
    throw Error('插件内容校验失败');
  if(!WebAssembly.validate(bytes))throw Error('无效的插件模块');
  let pos=8;
  function number(){
    let value=0,shift=0;
    while(pos<bytes.length && shift<=28){
      const next=bytes[pos++];value+=(next&127)*2**shift;
      if(next<128)return value;
      shift+=7;
    }
    throw Error('无效的模块区段');
  }
  while(pos<bytes.length){
    const section=bytes[pos++], size=number(), end=pos+size;
    if(![0,1,2,3,6,7,10].includes(section)){
      // AssemblyScript may emit an unused memory bounded to one 64 KiB page.
      if(section!==5 || number()!==1 || number()!==1 || number()>1 || number()>1 || pos!==end)
        throw Error('模块使用了不支持的资源');
    }
    pos=end;
  }
  const compiled=await WebAssembly.compile(bytes);
  if(!WebAssembly.Module.exports(compiled).some(item=>item.name==='step' && item.kind==='function'))
    throw Error('插件缺少 step 函数');
  const imports=WebAssembly.Module.imports(compiled);
  if(imports.some(i=>i.kind!=='function'||i.module!=='pet'||
    !(i.name==='save'&&m.capabilities.includes('state')||i.name==='play'&&m.capabilities.includes('motion'))))
    throw Error('插件请求了未授权的能力');
  return bytes;
}

// Check activation in isolation before committing a replacement to the pet.
async function checkModuleInstall(module){
  if(module.kind==='speech'){validateSpeech(module);return;}
  if(module.kind==='session-notice'){validateNotice(module);return;}
  if(module.kind==='state-machine'){validateMachine(module);return;}
  const bytes=await verifyModule(module);
  const url=URL.createObjectURL(new Blob(['('+pluginWorker.toString()+')()'],{type:'text/javascript'}));
  let worker,timeout;
  try{
    worker=new Worker(url);
    await new Promise((resolve,reject)=>{
      const fail=()=>reject(Error('插件启动失败或超时'));
      timeout=setTimeout(fail,3000);
      worker.onerror=fail;
      worker.onmessage=({data})=>{
        if(data.error){fail();return;}
        const index=module.events.indexOf('host.ready');
        if(data.ready && index>=0)worker.postMessage({index,state:0,now:Date.now()});
        else resolve();
      };
      worker.postMessage({bytes,capabilities:module.capabilities});
    });
  }finally{clearTimeout(timeout);worker?.terminate();URL.revokeObjectURL(url);}
}

function startPetModules(button,pet,feedback){
  const active=new Map();
  const states=pet.moduleState??={};
  const storageKey=id=>'jiumi-module-'+pet.id+'-'+id+'-'+pet.revision;
  function start(module){
    const key=storageKey(module.id);
    let state=states[module.id]??0;
    try{
      const cached=localStorage.getItem(key);
      if(cached!==null && Number.isSafeInteger(JSON.parse(cached)))state=JSON.parse(cached);
    }catch{}
    states[module.id]=state;
    let worker,url,deadline,busy=true,closed=false,closing=false;
    const pending=[];
    function close(){
      closed=true;clearTimeout(deadline);pending.length=0;worker?.terminate();
      if(url)URL.revokeObjectURL(url);
    }
    function stop(){
      const index=module.events.indexOf('host.stop');
      if(index<0||!worker||closed){close();return;}
      closing=true;pending.length=0;
      clearTimeout(deadline);deadline=setTimeout(close,250);
      worker.postMessage({index,state,now:Date.now(),terminal:true});
    }
    function fail(){
      close();button.dispatchEvent(new CustomEvent('plugin.error',{detail:module.id}));
    }
    function flush(){
      if(closed||busy||!pending.length)return;
      const index=pending.shift();
      busy=true;deadline=setTimeout(fail,1000);
      worker.postMessage({index,state,now:Date.now()});
    }
    function send(event){
      const index=module.events.indexOf(event);
      if(index<0||closed||pending.length>=32)return;
      pending.push(index);flush();
    }
    async function boot(){
      try{
        const bytes=await verifyModule(module);
        if(closed)return;
        url=URL.createObjectURL(new Blob(['('+pluginWorker.toString()+')()'],{type:'text/javascript'}));
        worker=new Worker(url);
        worker.onerror=fail;
        worker.onmessage=({data})=>{
          if(closing){if(data.terminal||data.error)close();return;}
          clearTimeout(deadline);
          if(closed)return;
          if(data.error){fail();return;}
          if(data.writes!==undefined){
            state=states[module.id]=data.writes;
            try{localStorage.setItem(key,JSON.stringify(state))}catch{}
          }
          if(data.writes!==undefined)window.webkit?.messageHandlers?.progress?.postMessage({id:pet.id,revision:pet.revision,key:module.id,value:state});
          if(data.action)feedback.play(data.action===1?'focus':'greet',1);
          busy=false;flush();
        };
        deadline=setTimeout(fail,3000);
        worker.postMessage({bytes,capabilities:module.capabilities});
      }catch{fail();}
    }
    boot();send('host.ready');
    return {send,close:stop};
  }
  let tick=null,visible=!document.hidden;
  function sync(){
    for(const [id,runner] of active)if(!pet.plugins.includes(id)){
      runner.close();active.delete(id);
    }
    for(const module of (pet.modules||[]).slice(0,8)){
      if(!['state-machine','session-notice','speech'].includes(module.kind) && pet.plugins.includes(module.id)&&!active.has(module.id))active.set(module.id,start(module));
    }
    if(active.size && !tick)tick=setInterval(()=>{if(!button.isConnected){dispose();return;}if(visible && !document.hidden)send('host.tick')},1000);
    if(!active.size){clearInterval(tick);tick=null;}
  }
  function send(type){for(const runner of active.values())runner.send(type);}
  function dispose(){clearInterval(tick);for(const runner of active.values())runner.close();active.clear();}
  sync();
  return {send,dispose,sync,setVisible(value){visible=value;send(value?'host.resume':'host.hide');}};
}
