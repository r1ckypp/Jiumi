// Declarative modules own their graph. The host owns arbitration and playback.
function validateMachine(m){
  const record=x=>x!==null && typeof x==='object' && !Array.isArray(x);
  const key=x=>typeof x==='string' && /^[a-z][a-z0-9-]{0,47}$/.test(x) && x!=='constructor';
  const fail=()=>{throw Error('状态插件格式或转移目标无效')};
  if(!record(m)||m.kind!=='state-machine'||m.api!==1||!key(m.id)||
     !Number.isSafeInteger(m.version)||m.version<1||typeof m.name!=='string'||!m.name.length||m.name.length>80||
     !Number.isInteger(m.priority)||m.priority<0||m.priority>100||!record(m.states))fail();
  const keys=Object.keys(m.states);
  if(!keys.length||keys.length>32||!keys.every(k=>key(k)&&k!=='free'))fail();
  const local=t=>typeof t==='string'&&Object.hasOwn(m.states,t);
  const exit=t=>local(t)||t==='$resume'||t==='$base';
  function routes(table,allow){
    if(!record(table)||Object.keys(table).length>32)fail();
    for(const [event,target] of Object.entries(table))
      if(!event.length||event.length>160||!allow(target))fail();
  }
  routes(m.enter,local);
  if(!Object.keys(m.enter).length)fail();
  if(m.menu!==undefined){
    if(!record(m.menu)||Object.keys(m.menu).length>8)fail();
    for(const [id,label] of Object.entries(m.menu)){
      if(!key(id)||typeof label!=='string'||!label.trim()||label.length>80||
         !Object.hasOwn(m.enter,'menu.'+m.id+'.'+id))fail();
    }
  }
  for(const s of Object.values(m.states)){
    if(!record(s)||!key(s.motion))fail();
    if(s.timeoutMs!==undefined && (!Number.isSafeInteger(s.timeoutMs)||s.timeoutMs<1||s.timeoutMs>2147483647))fail();
    if(s.on!==undefined)routes(s.on,exit);
    if(s.resumeAt!==undefined && !local(s.resumeAt) && !['$self','$discard'].includes(s.resumeAt))fail();
    if(s.after!==undefined && !exit(s.after))fail();
  }
  for(const start of keys){
    const visited=new Set();
    for(let k=start;local(k);k=m.states[k].after){
      if(visited.has(k))fail();
      visited.add(k);
    }
  }
}

function interactionMachine(modules,render){
  const sort=list=>[...list].sort((a,b)=>b.priority-a.priority || (a.id<b.id?-1:1));
  let ordered=sort(modules);
  const paused=[];
  let current=null;
  const route=(map,event)=>map && Object.hasOwn(map,event)?map[event]:undefined;
  function cancel(frame){
    if(frame?.timer!==undefined)clearTimeout(frame.timer);
  }
  function discardPaused(from){
    paused.splice(from).forEach(cancel);
  }
  function frameFor(module,key){
    const frame={module,key};
    const duration=module.states[key].timeoutMs;
    if(duration!==undefined){
      frame.timer=setTimeout(()=>{
        if(current===frame)move(module,'$resume');
        else {
          const index=paused.indexOf(frame);
          if(index>=0)paused.splice(index,1);
        }
      },duration);
    }
    return frame;
  }
  function move(module,target){
    cancel(current);
    if(target==='$base')discardPaused(0);
    current=target==='$base'||target==='$resume'?paused.pop()??null:frameFor(module,target);
    render(current);
  }
  function dispatch(event){
    // Keep interrupted states up to date (e.g. releasing a suspended grab).
    for(let i=paused.length-1;i>=0;i--){
      const frame=paused[i],target=route(frame.module.states[frame.key].on,event);
      if(target==='$base')paused.splice(0,i+1).forEach(cancel);
      else if(target==='$resume')paused.splice(i,1).forEach(cancel);
      else if(target){cancel(frame);paused[i]=frameFor(frame.module,target);}
      if(target==='$base')break;
    }
    if(current){
      const next=route(current.module.states[current.key].on,event);
      if(next){move(current.module,next);return;}
    }
    const owner=ordered.find(m=>route(m.enter,event) && (!current||m.priority>current.module.priority));
    if(!owner)return;
    if(current){
      const resume=current.module.states[current.key].resumeAt??'$self';
      if(resume==='$self'){paused.push(current);current=null;}
      else if(resume!=='$discard')paused.push(frameFor(current.module,resume));
    }
    move(owner,owner.enter[event]);
  }
  function replace(list){
    ordered=sort(list);
    for(let i=paused.length-1;i>=0;i--)if(!ordered.includes(paused[i].module))paused.splice(i,1).forEach(cancel);
    if(current && !ordered.includes(current.module))move(current.module,'$resume');
  }
  return {dispatch,move,replace,clear(){discardPaused(0);cancel(current);current=null;}};
}

function petMachines(pet){
  const installed=pet.modules??[];
  const enabled=installed.filter(m=>m.kind==='state-machine' && pet.plugins.includes(m.id));
  if(!installed.some(m=>m.id===defaultPickup.id))enabled.push(defaultPickup);
  return enabled;
}
