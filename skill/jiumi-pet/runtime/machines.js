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
  for(const s of Object.values(m.states)){
    if(!record(s)||!key(s.motion))fail();
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
  const ordered=[...modules].sort((a,b)=>b.priority-a.priority || (a.id<b.id?-1:1));
  const paused=[];
  let current=null;
  const route=(map,event)=>map && Object.hasOwn(map,event)?map[event]:undefined;
  function move(module,target){
    if(target==='$base')paused.length=0;
    current=target==='$base'||target==='$resume'?paused.pop()??null:{module,key:target};
    render(current);
  }
  function dispatch(event){
    // Keep interrupted states up to date (e.g. releasing a suspended grab).
    for(let i=paused.length-1;i>=0;i--){
      const frame=paused[i],target=route(frame.module.states[frame.key].on,event);
      if(target==='$base')paused.splice(0,i+1);
      else if(target==='$resume')paused.splice(i,1);
      else if(target)frame.key=target;
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
      if(resume!=='$discard')paused.push({module:current.module,key:resume==='$self'?current.key:resume});
    }
    move(owner,owner.enter[event]);
  }
  return {dispatch,move,clear(){paused.length=0;current=null;}};
}

function petMachines(pet){
  const installed=pet.modules??[];
  const enabled=installed.filter(m=>m.kind==='state-machine' && pet.plugins.includes(m.id));
  if(!installed.some(m=>m.id===defaultPickup.id))enabled.push(defaultPickup);
  return enabled;
}
