function validateSpeech(m){
  const seconds=n=>Number.isInteger(n)&&n>=1&&n<=3600;
  if(!m || m.kind!=='speech' || m.api!==1 || !Number.isSafeInteger(m.version) || m.version<1 ||
     typeof m.id!=='string' || !/^[a-z][a-z0-9-]{0,47}$/.test(m.id) || m.id==='constructor' ||
     typeof m.name!=='string' || !m.name.trim() || m.name.length>80 ||
     !seconds(m.minSeconds) || !seconds(m.maxSeconds) || m.minSeconds>m.maxSeconds ||
     !seconds(m.durationSeconds) || m.durationSeconds>30 ||
     !Array.isArray(m.lines) || !m.lines.length || m.lines.length>100 ||
     m.lines.some(line=>typeof line!=='string' || !line.trim() || line.length>48))
    throw Error('气泡插件格式无效');
}

function attachSpeech(stage,pet,host){
  const packs=(pet.modules??[]).filter(m=>m.kind==='speech');
  if(!packs.length)return;
  const bubble=document.createElement('span');
  bubble.dataset.petSpeech='';
  bubble.setAttribute('role','status');
  bubble.style.cssText='position:absolute;z-index:4;left:50%;bottom:88%;transform:translateX(-50%);box-sizing:border-box;width:max-content;max-width:96%;padding:6px 10px;border:1px solid #d3c5a9;border-radius:14px 14px 14px 4px;background:#fffaf0;color:#493d31;font:13px/1.4 system-ui;text-align:center;overflow-wrap:anywhere;pointer-events:none;box-shadow:0 2px 5px #493d3118';
  bubble.hidden=true;
  stage.append(bubble);
  const motion=stage.feedback;
  let visible=!document.hidden, blocked=false, timer, previous='';
  function hide(){
    if(bubble.hidden)return;
    bubble.hidden=true;bubble.textContent='';
    host?.speechLayout?.(false);
  }
  function schedule(){
    clearTimeout(timer);
    hide();
    const enabled=packs.filter(m=>pet.plugins.includes(m.id));
    if(!visible || blocked || !enabled.length)return;
    const pack=enabled[Math.floor(Math.random()*enabled.length)];
    timer=setTimeout(()=>{
      const alternatives=pack.lines.filter(line=>line!==previous);
      const options=alternatives.length?alternatives:pack.lines;
      previous=options[Math.floor(Math.random()*options.length)];
      bubble.textContent=pack.id===defaultSpeech.id?ui(previous):previous;bubble.hidden=false;
      host?.speechLayout?.(true);
      timer=setTimeout(schedule,pack.durationSeconds*1000);
    },1000*(pack.minSeconds+Math.random()*(pack.maxSeconds-pack.minSeconds)));
  }
  const {setVisible,dispose}=motion;
  motion.setVisible=value=>{
    setVisible(value);
    if(visible!==value){visible=value;schedule();}
  };
  motion.setSpeechBlocked=value=>{
    if(blocked!==value){blocked=value;schedule();}
  };
  motion.syncSpeech=schedule;
  motion.dispose=()=>{clearTimeout(timer);hide();bubble.remove();dispose();};
  schedule();
}
