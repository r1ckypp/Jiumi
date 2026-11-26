/*!
MIT License

Copyright (c) 2026 Jiumi contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
// Transform the whole illustration around its feet; the source PNG stays untouched.
const petMotions = {
  focus: ['专注',3000,['rotate(-2deg)','translateY(1px) rotate(-4deg)','rotate(-2deg)']],
  expect: ['等待',3200,['rotate(5deg)','translateY(-2px) rotate(6deg)','rotate(5deg)']],
  idle: ['呼吸',2600,['none','translateY(-2px) scale(1.015,1.025)','none']],
  greet: ['招呼',900,['none','rotate(-11deg)','rotate(8deg)','rotate(-5deg)','none']],
  peek: ['探头',1500,['none','translateX(7px) rotate(10deg)','translateX(7px) rotate(10deg)','none']],
  walk: ['散步',1900,['none','translate(-7px,-3px) rotate(-6deg)','translateX(-13px)','translate(-7px,-3px) rotate(5deg)','none','translate(7px,-3px) rotate(6deg)','translateX(13px)','translate(7px,-3px) rotate(-5deg)','none']],
  hop: ['开心跳',850,['none','scale(1.10,.88)','translateY(-17px) rotate(-5deg)','scale(1.07,.93)','translateY(-5px)','none']],
  pet: ['被摸',650,['none','rotate(-9deg) scale(1.06,.91)','rotate(-6deg) scale(1.05,.94)','rotate(3deg)','none']],
  held: ['被拎起',480,['translateY(-10px) rotate(-7deg) scale(.97,1.05)','translateY(-12px) rotate(7deg) scale(.96,1.07)','translateY(-10px) rotate(-7deg) scale(.97,1.05)']],
  landing: ['落地',440,['translateY(-12px) scale(.97,1.05)','translateY(0) scale(1.16,.81)','translateY(-5px) scale(.95,1.06)','translateY(0) scale(1.04,.96)','none']],
  nap: ['打盹',2300,['none','rotate(7deg) scale(1.04,.88)','rotate(7deg) scale(1.06,.90)','rotate(7deg) scale(1.04,.88)','none']]
};

// State and arbitration contain no browser or transport dependencies.
function createFeedback({body, effect, stateChanged=()=>{}, interactionChanged=()=>{}, machines=[defaultPickup],rules=[], clock=Date.now}){
  const sessions=new Map(), seen=new Map();
  const phases=new Map([['agent.started','working'],['agent.resumed','working'],
    ['agent.input_requested','waiting'],['agent.completed','ended'],['agent.closed','ended']]);
  const defaults=[
    {on:'pet.tap',intent:'affection'},
    {on:'agent.input_requested',intent:'attention'},
    {on:'agent.completed',intent:'celebrate'}
  ];
  const priority={affection:3,attention:2,celebrate:1};
  let interaction='free';
  let state='idle',active=null,version=0,visible=true,disposed=false;
  const reactions=[...defaults.filter(d=>!rules.some(r=>r.on===d.on && Object.hasOwn(priority,r.intent))),...rules];
  function base(){
    if(visible && !disposed && !active && interaction==='free')body(state,null);
  }
  function update(){
    const values=[...sessions.values()];
    const next=values.some(s=>s.phase==='waiting')?'waiting':values.some(s=>s.phase==='working')?'working':'idle';
    if(next!==state){state=next;stateChanged(state);base()}
  }
  function expire(now){
    for(const [key,s] of sessions)if(now-s.at>=300000)sessions.delete(key);
    update();
  }
  function play(intent,level=4){
    if(!visible || disposed || interaction!=='free' || (active && active.level>level))return;
    const current=++version;
    active={level};
    body(intent,()=>{if(current===version){active=null;base()}});
  }
  let interactionMotion=null;
  const machine=interactionMachine(machines,frame=>{
    interaction=frame?.key??'free';
    const definition=frame?.module.states[frame.key];
    interactionMotion=definition?.motion??null;
    active=null;
    const generation=++version;
    interactionChanged(interaction,frame?.module.id);
    if(!frame){base();return;}
    const done=definition.after ? ()=>{
      if(generation===version)machine.move(frame.module,definition.after);
    } : null;
    body(interactionMotion,done);
  });
  function dispatch(e){
    const now=clock();
    if(disposed || !e || e.v!==1 || ![e.id,e.source,e.type].every(x=>typeof x==='string' && x.length && x.length<=160)
      || !Number.isSafeInteger(e.at) || e.at>now+5000 || now-e.at>=300000)return false;
    const id=JSON.stringify([e.source,e.id]);
    if(seen.has(id))return false;
    seen.set(id,true);
    if(seen.size>1024)seen.delete(seen.keys().next().value);
    expire(now);
    if(phases.has(e.type)){
      if(typeof e.session!=='string' || !e.session.length || e.session.length>160)return false;
      const key=JSON.stringify([e.source,e.session]),prev=sessions.get(key),phase=phases.get(e.type);
      if(prev && e.at<prev.at)return false;
      sessions.set(key,{phase,at:e.at});
      update();
      if(prev?.phase===phase)return true;
    }
    if(!visible || now-e.at>15000)return true;
    machine.dispatch(e.type);
    for(const rule of reactions){
      if(rule.on!==e.type)continue;
      if(rule.effect==='particles')effect(rule);
      if(Object.hasOwn(priority,rule.intent))play(rule.intent,priority[rule.intent]);
    }
    return true;
  }
  function setVisible(value){
    if(value===visible)return;
    visible=value;active=null;++version;
    machine.clear();interactionMotion=null;interaction='free';interactionChanged(interaction);
    if(!value)body('silent',null);else{expire(clock());base()}
  }
  function disconnect(source){
    for(const key of sessions.keys())if(JSON.parse(key)[0]===source)sessions.delete(key);
    update();
  }
  base();
  return {dispatch,play,setVisible,disconnect,tick:()=>expire(clock()),getState:()=>state,getInteraction:()=>interaction,getBodyIntent:()=>interactionMotion??state,
    dispose(){disposed=true;++version;sessions.clear();seen.clear();body('silent',null)}};
}

function animatePet(button,picture,pet,catalog){
  let animation, breaths=0, turn=0;
  const lastSelection=new Map();
  let frameTimer, framePicture;
  function stopFrames(){
    clearTimeout(frameTimer);
    framePicture?.remove();
    framePicture=null;
    picture.hidden=false;
  }
  const routine=['peek','walk','nap'];
  const mapping={affection:'pet',attention:'peek',celebrate:'hop',waiting:'expect',working:'focus',idle:'idle'};
  picture.style.transformOrigin='50% 85%';
  function body(intent,done){
    if(animation){animation.onfinish=null;animation.cancel();animation=null}
    stopFrames();
    picture.stopPose?.();
    if(intent==='silent')return;
    picture.style.transformOrigin=intent==='held'?'50% 12%':'50% 85%';
    const override=pet.appearance?.motions?.[intent];
    const authored=pet.rig?.poses??{};
    const known=key=>typeof key==='string' && (Object.hasOwn(petMotions,key)||Object.hasOwn(pet.clips??{},key)||Object.hasOwn(authored,key));
    const pool=Object.hasOwn(pet.motionPools??{},intent)?pet.motionPools[intent].filter(known):[];
    const choices=pool.length>1?pool.filter(key=>key!==lastSelection.get(intent)):pool;
    let name=known(override)?override:mapping[intent]||intent;
    if(Object.hasOwn(pet.clips??{},intent) && !known(override))name=intent;
    else if(choices.length && !known(override)){
      name=choices[Math.floor(Math.random()*choices.length)];
      lastSelection.set(intent,name);
    }
    if(!known(name))name='idle';
    if(!pool.length && !known(override) && !pet.clips?.idle && intent==='idle' && !done && ++breaths%5===0)name=routine[turn++%routine.length];
    button.dataset.motion=name;
    if(matchMedia('(prefers-reduced-motion: reduce)').matches){if(done)queueMicrotask(done);return}
    const clip=pet.clips?.[name];
    if(clip?.frames?.length){
      framePicture=new Image();
      framePicture.style.cssText=picture.style.cssText;
      picture.hidden=true;
      picture.after(framePicture);
      let index=0;
      function advance(){
        if(index>0 && !picture.isConnected){stopFrames();return}
        if(index===clip.frames.length){
          if(done){done();return}
          if(pool.length && !known(override)){
            const previous=framePicture;
            engine.tick();
            if(framePicture===previous && engine.getBodyIntent()===intent)body(intent,null);
            return;
          }
          if(!clip.loop){
            engine.tick();
            if(framePicture && button.dataset.motion===name)frameTimer=setTimeout(advance,1000);
            return;
          }
          engine.tick();
          if(button.dataset.motion!==name || !framePicture)return;
          index=0;
        }
        framePicture.src=clip.frames[index++];
        frameTimer=setTimeout(advance,clip.frameMs);
      }
      advance();
      return;
    }
    const [,baseDuration,poses]=petMotions[name]??[name,0,['none','none']];
    const duration=authored[name]?.duration??baseDuration;
    picture.pose?.(name,duration);
    animation=picture.animate(poses.map(transform=>({transform})),{duration,easing:'ease-in-out'});
    animation.onfinish=()=>{
      if(!picture.isConnected)return;
      if(done)done();else{engine.tick();if(engine.getBodyIntent()===intent)body(intent,null)}
    };
  }
  function effect(rule){
    if(matchMedia('(prefers-reduced-motion: reduce)').matches)return;
    for(let i=0;i<6;i++){
      const flake=document.createElement('span');flake.textContent=rule.symbol;
      flake.style.cssText='position:absolute;left:'+ (15+i*12)+'%;top:10%;pointer-events:none';
      button.append(flake);
      flake.animate([{transform:'translateY(0)',opacity:1},{transform:'translateY(55px) rotate(80deg)',opacity:0}],{duration:800+i*60}).onfinish=()=>flake.remove();
    }
  }
  const engine=createFeedback({body,effect,machines:petMachines(pet),interactionChanged:value=>{button.dataset.interaction=value},rules:catalog.filter(r=>pet.plugins.includes(r.id)),
    stateChanged:state=>{button.dataset.state=state;button.setAttribute('aria-label',ui('摸摸')+pet.name+' · '+ui({idle:'待机',working:'工作中',waiting:'等待确认'}[state]))}});
  button.dataset.state='idle';button.dataset.interaction='free';
  return engine;
}

function petMotionMenu(select,getPlayer,pet){
  const extra=new Set([...Object.keys(pet?.clips??{}),...Object.keys(pet?.rig?.poses??{})]);
  for(const machine of petMachines(pet??{plugins:[]})){
    for(const state of Object.values(machine.states))extra.add(state.motion);
  }
  select.replaceChildren(...Object.entries(petMotions).map(([key,[label]])=>new Option(ui(label),key)));
  for(const name of extra)if(!Object.hasOwn(petMotions,name))select.add(new Option(pet?.clips?.[name]?.label||pet?.rig?.poses?.[name]?.label||name,name));
  select.onchange=()=>getPlayer().play(select.value);
}
// A short press is a tap. Holding picks the pet up until release or cancellation.
function petHands(button,feedback){
  if(!document.getElementById('jiumi-hand-styles')){
    const style=document.createElement('style');
    style.id='jiumi-hand-styles';
    style.textContent=`
      [data-pet-touch]{touch-action:none;user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;cursor:grab}
      [data-pet-touch="held"]{cursor:grabbing}
      [data-pet-touch="held"]>img:not(:first-child){translate:0 -7%;rotate:-3deg}
      .jiumi-hand{position:absolute;z-index:2;top:1%;left:52%;font:28px/1 "Apple Color Emoji","Segoe UI Emoji",sans-serif;pointer-events:none}
      [data-pet-touch="held"] .jiumi-hand{animation:jiumi-pinch .16s ease-out both}
      @keyframes jiumi-pinch{from{transform:translateY(-7px) scale(1.12)}to{transform:translateY(0) rotate(-10deg)}}
      @media(prefers-reduced-motion:reduce){[data-pet-touch="held"] .jiumi-hand{animation:none}}
    `;
    document.head.append(style);
  }
  const hand=document.createElement('span');
  hand.className='jiumi-hand';hand.setAttribute('aria-hidden','true');hand.hidden=true;button.append(hand);
  button.dataset.petTouch='idle';
  const bridge=window.webkit?.messageHandlers?.petGrab;
  const listeners=new AbortController();
  let pointer=null,holdTimer,handTimer,held=false,skipClick=false,startX,startY,offsetX=0,offsetY=0;
  function on(target,event,fn){target.addEventListener(event,fn,{signal:listeners.signal});}
  let gestureID=0;
  function report(type){feedback.dispatch({v:1,id:'gesture-'+(++gestureID),source:'pointer',type,at:Date.now()});}
  function finish(released=false){
    clearTimeout(holdTimer);
    if(held){
      bridge?.postMessage('end');
      hand.hidden=true;
      button.dataset.petTouch='idle';
      report(released===true?'pet.release':'pet.cancel');
    }
    held=false;pointer=null;
  }
  on(button,'pointerdown',e=>{
    if(e.button!==0||!e.isPrimary||pointer!==null)return;
    pointer=e.pointerId;skipClick=false;
    startX=e.clientX-offsetX;startY=e.clientY-offsetY;
    button.setPointerCapture(pointer);
    holdTimer=setTimeout(()=>{
      held=true;skipClick=true;
      clearTimeout(handTimer);hand.getAnimations().forEach(a=>a.cancel());
      hand.textContent='🤏';hand.hidden=false;button.dataset.petTouch='held';
      report('pet.grab');
      bridge?.postMessage('begin');
    },100);
  });
  on(button,'pointermove',e=>{
    if(!held||e.pointerId!==pointer||bridge||!button.hasAttribute('data-movable'))return;
    const movable=button.closest('[data-pet-body]')||button;
    const box=movable.getBoundingClientRect();
    const x=box.left-offsetX,y=box.top-offsetY;
    const bounds=button.closest('[data-pet-bounds]')?.getBoundingClientRect()??{left:0,top:0,right:innerWidth,bottom:innerHeight};
    offsetX=Math.max(bounds.left-x,Math.min(bounds.right-box.width-x,e.clientX-startX));
    offsetY=Math.max(bounds.top-y,Math.min(bounds.bottom-box.height-y,e.clientY-startY));
    movable.style.translate=offsetX+'px '+offsetY+'px';
  });
  for(const event of ['pointerup','pointercancel','lostpointercapture']){
    on(button,event,e=>{if(e.pointerId===pointer)finish(event==='pointerup')});
  }
  on(window,'blur',finish);
  on(document,'visibilitychange',()=>{if(document.hidden)finish()});
  return {
    stroke(event){
      if(skipClick && event.detail!==0){skipClick=false;return false;}
      clearTimeout(handTimer);hand.getAnimations().forEach(a=>a.cancel());
      hand.textContent='🫳';hand.hidden=false;
      if(!matchMedia('(prefers-reduced-motion: reduce)').matches){
        hand.animate([{transform:'translate(-8px,-5px) rotate(-13deg)'},{transform:'translate(7px,4px) rotate(9deg)'},{transform:'translate(-4px,0) rotate(-6deg)'},{transform:'translate(5px,-4px)',opacity:0}],{duration:550});
      }
      handTimer=setTimeout(()=>{hand.hidden=true},550);
      return true;
    },
    dispose(){finish();clearTimeout(handTimer);listeners.abort();hand.remove();}
  };
}
function attachPetMenu(stage,pet,nativeMenu){
  const items=petMachines(pet).flatMap(module=>Object.entries(module.menu??{}).map(([key,label])=>({
    event:'menu.'+module.id+'.'+key, label:ui(label)
  })));
  const feedback=stage.feedback;
  feedback.menuItems=items;
  feedback.selectMenu=event=>{
    if(!items.some(item=>item.event===event))return false;
    return feedback.dispatch({v:1,id:crypto.randomUUID(),source:'menu',type:event,at:Date.now()});
  };
  if(nativeMenu || !items.length)return;
  const select=document.createElement('select');
  select.setAttribute('aria-label',ui('互动'));
  select.add(new Option(ui('互动'),''));
  for(const item of items)select.add(new Option(item.label,item.event));
  select.onchange=()=>{feedback.selectMenu(select.value);select.selectedIndex=0;};
  stage.after(select);
  const dispose=feedback.dispose;
  feedback.dispose=()=>{select.remove();dispose();};
}

function mountPet(button, pet, catalog, host) {
  button.feedback?.dispose();
  button.replaceChildren();
  button.setAttribute('aria-label',ui('摸摸')+pet.name);
  const appearance=pet.appearance || {};
  let picture=pet.rig && typeof rigPicture==='function'?rigPicture(pet):null;
  if (!picture && pet.image) {
    picture = new Image(); picture.src = pet.image;
  } else if(!picture){
    const rows = ['..##.....##...','..#o#...#o#...','..#oo###oo#...','.LoooooooooL..','.LoxoooxoooL..','.LooOnOooooL..','..LooOOoooL...','...LooooooL..#','...LoOOOooL.#o','..LooOOOooo#o#','..LoooooooL##.','..####.####...'];
    const colors = {'#':'#563d39',L:'#805045',o:pet.color,x:appearance.eyes || '#352a2d',O:'#fff2d8',n:appearance.nose || '#c86a70'};
    picture = document.createElement('canvas'); picture.width=15; picture.height=12+(appearance.ears || 3)-3;
    const pen=picture.getContext('2d');
    const ears=appearance.ears || 3;
    const pixels=Array.from({length:ears},(_,i)=>rows[Math.floor(i*3/ears)]).concat(rows.slice(3));
    pixels.forEach((row,y)=>Array.from(row).forEach((p,x)=>{if(colors[p]){pen.fillStyle=y<ears && p==="o" ? (appearance.inner || pet.color) : colors[p];pen.fillRect(x,y,1,1);}}));
  }
  picture.style.cssText='width:86%;height:86%;object-fit:contain;image-rendering:pixelated;pointer-events:none';
  if(pet.image || pet.rig){
    picture.style.imageRendering='auto';
    if(Number.isFinite(appearance.hue))picture.style.filter='hue-rotate('+appearance.hue+'deg)';
  }
  picture.style.scale=String((appearance.scale || 100)/100);
  if(pet.rig){picture.style.margin='auto';picture.style.verticalAlign='middle';}
  button.append(picture);
  const motion=animatePet(button,picture,pet,catalog);
  if(pet.modules?.length && typeof startPetModules==='function'){
    const modules=startPetModules(button,pet,motion);
    const {dispatch,dispose,setVisible}=motion;
    motion.dispatch=event=>{
      const accepted=dispatch(event);
      if(accepted && !event.type.startsWith('host.'))modules.send(event.type);
      return accepted;
    };
    motion.dispose=()=>{modules.dispose();dispose();};
    let moduleVisible=true;
    motion.setVisible=value=>{
      if(value===moduleVisible)return;
      moduleVisible=value;
      setVisible(value);
      modules.send(value?'host.resume':'host.hide');
    };
  }
  button.feedback=motion;
  if(document.hidden)motion.setVisible(false);
  let count=0;
  const hands=petHands(button,motion);
  const dispose=motion.dispose;
  motion.dispose=()=>{hands.dispose();dispose();};
  button.onclick=event=>{
    if(!hands.stroke(event))return;
    count++;
    motion.dispatch({v:1,id:String(count),source:'pointer',type:'pet.tap',at:Date.now()});
    button.dispatchEvent(new CustomEvent('pet.tap',{detail:{count}}));
  };
  attachSessionNotices(button,pet,host);
  attachPetMenu(button,pet,host?.nativeMenu);
  return motion;
}

if(typeof document!=='undefined'){
  document.addEventListener('visibilitychange',()=>{
    for(const button of document.querySelectorAll('button[data-state]')){
      button.feedback?.setVisible(!document.hidden);
    }
  });
}
