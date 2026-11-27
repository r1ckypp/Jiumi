// Session notices have their own lifetime, independent of the body animation.
function validateNotice(m){
  const label=(s,n)=>typeof s==='string' && s.trim().length>0 && s.length<=n;
  if(m.api!==1 || !Number.isSafeInteger(m.version) || m.version<1 ||
     typeof m.id!=='string' || !/^[a-z][a-z0-9-]{0,47}$/.test(m.id) || m.id==='constructor' ||
     !label(m.name,80) || !label(m.title,80) || !label(m.show,160) || m.action!=='session.open' ||
     !Array.isArray(m.clear) || !m.clear.length || m.clear.length>16 ||
     !m.clear.every(e=>label(e,160) && e!==m.show))throw Error('会话提示插件格式无效');
}

function attachSessionNotices(stage,pet,host){
  const installed=(pet.modules??[]).filter(m=>m.kind==='session-notice');
  if(!installed.length)return;
  let rules=installed.filter(m=>pet.plugins.includes(m.id));
  const panel=document.createElement('aside');
  panel.setAttribute('aria-live','polite');
  panel.style.cssText='position:relative;box-sizing:border-box;margin:2px auto;width:min(100%,220px);max-height:110px;overflow:auto;border-radius:10px;background:#fff8e8;color:#49372d;padding:6px;font:13px/1.3 system-ui;text-align:center;overflow-wrap:anywhere';
  panel.hidden=true;
  stage.after(panel);
  const notices=new Map();
  const pending=()=>Array.from(notices.values()).at(-1);
  let generation=0;
  function render(){
    const token=++generation;
    const item=pending();
    panel.replaceChildren();
    panel.hidden=!item;
    stage.feedback.setSpeechBlocked?.(Boolean(item));
    host?.layout?.(Boolean(item));
    if(!item)return;
    const title=document.createElement('strong');
    title.textContent=item.rule.title;
    const summary=document.createElement('div');
    summary.textContent=item.summary;
    const detail=document.createElement('small');
    detail.textContent=item.source+' · '+item.session;
    panel.append(title,summary,detail);
    if(!host?.session)return;
    const target={source:item.source,session:item.session};
    Promise.resolve().then(()=>host.session('available',target)).then(available=>{
      if(token!==generation || !available)return;
      const open=document.createElement('button');
      open.type='button';open.textContent=ui('回到会话');
      open.style.cssText='position:relative;display:block;width:auto;height:auto;margin:3px auto;padding:3px 9px;color:#fff;background:#345c43;border:0;border-radius:6px;font:inherit';
      panel.append(open);
      open.onclick=async e=>{
        if(!e.isTrusted)return;
        open.disabled=true;
        let ok=false;
        try{ok=await host.session('open',target);}catch{}
        if(token!==generation)return;
        open.disabled=false;
        if(!ok)detail.textContent=ui('打开失败，可手动返回 ')+item.source+' · '+item.session;
        stage.dispatchEvent(new CustomEvent('pet.action',{detail:{action:item.rule.action,...target,ok}}));
      };
    }).catch(()=>{});
  }
  const feedback=stage.feedback;
  const {dispatch,dispose,disconnect}=feedback;
  feedback.dispatch=e=>{
    if(!dispatch(e))return false;
    if(typeof e.session!=='string'||!e.session.trim()||e.session.length>160)return true;
    let changed=false;
    for(const rule of rules){
      const key=JSON.stringify([rule.id,e.source,e.session]);
      if(rule.clear.includes(e.type)){changed=notices.delete(key)||changed;continue;}
      if(rule.show!==e.type)continue;
      notices.delete(key);
      notices.set(key,{rule,source:e.source,session:e.session,summary:typeof e.summary==='string'?e.summary.trim().slice(0,160):''});
      if(notices.size>32)notices.delete(notices.keys().next().value);
      changed=true;
    }
    if(changed)render();
    return true;
  };
  feedback.syncNotices=()=>{
    rules=installed.filter(m=>pet.plugins.includes(m.id));
    for(const [key,item] of notices)if(!rules.includes(item.rule))notices.delete(key);
    render();
  };
  feedback.disconnect=source=>{
    disconnect(source);
    for(const [key,item] of notices)if(item.source===source)notices.delete(key);
    render();
  };
  feedback.dispose=()=>{generation++;host?.layout?.(false);panel.remove();dispose();};
}

// An explicit local sample for standalone files with no connected event adapter.
function addNoticeSample(stage,pet,parent){
  const rule=(pet.modules??[]).find(m=>m.kind==='session-notice' && pet.plugins.includes(m.id));
  if(!rule)return;
  const sample=document.createElement('button');
  sample.type='button';sample.dataset.label='试用会话提醒';sample.textContent=ui(sample.dataset.label);
  sample.style.cssText='width:auto;height:auto;padding:5px 10px';
  let waiting=false;
  sample.onclick=()=>{
    waiting=!waiting;
    stage.feedback.dispatch({v:1,id:crypto.randomUUID(),at:Date.now(),source:ui('离线示例'),session:ui('示例会话'),
      type:waiting?rule.show:rule.clear[0],summary:ui('蓝色小猪的预览已就绪，请检查外观。')});
    sample.dataset.label=waiting?'结束示例提醒':'试用会话提醒';sample.textContent=ui(sample.dataset.label);
  };
  parent.append(sample);
}
