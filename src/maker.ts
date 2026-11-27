declare function ui(label:string):string;
interface Preset { label: string; image: string }
type Presets = Record<string, Preset>;

function bluePig(blinking=false): string {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 128;
  const ctx = canvas.getContext('2d')!;
  ctx.strokeStyle = '#483a42';
  ctx.lineWidth = 3.5;
  function shape(path: string, color: string) {
    const outline = new Path2D(path);
    ctx.fillStyle = color;
    ctx.fill(outline);
    ctx.stroke(outline);
  }
  shape('M33 91 Q30 111 42 109 L49 98 M78 98 L84 109 Q98 114 94 91', '#74acca');
  shape('M22 56 Q22 33 42 33 L86 33 Q108 34 108 56 L108 80 Q107 102 87 103 L44 103 Q21 102 22 81 Z', '#98d6ee');
  shape('M27 52 Q13 25 26 24 Q44 25 47 36 Z M82 35 Q91 19 104 24 Q113 31 101 49 Z', '#96cfe7');
  shape('M53 75 Q53 65 66 65 L77 65 Q91 66 88 78 Q86 84 72 84 Q54 85 53 75 Z', '#f1b8ba');
  ctx.fillStyle = '#483a42';
  for (const [x,y,r] of [[48,59,3.5],[88,59,3.5],[65,75,2],[77,75,2]]) {
    ctx.beginPath();
    if(blinking && y===59){
      ctx.moveTo(x-r,y);ctx.quadraticCurveTo(x,y+2,x+r,y);ctx.stroke();
    }else{ctx.arc(x,y,r,0,Math.PI*2);ctx.fill();}

  }
  return canvas.toDataURL('image/png');
}

function makerPresets(official: Presets): Presets {
  return official.pig ? official : {
    chick: official.chick ?? {label:'方糖小鸡',image:''}, cat: {label:'方糖猫', image:''}, pig: {label:'蓝色小猪', image:bluePig()}
  };
}

function sugarPreset(species:string, image:string): Pick<PetPackage,'rig'|'color'> {
  const colors:Record<string,string>={chick:'#fac763',pig:'#99d3ec',cat:'#edb278',cow:'#f4ecdc',bunny:'#ecd6d5',elephant:'#adbbd8'};
  return {rig:species==='chick' && image ? undefined : {kind:'sugar',species},color:colors[species]??colors.chick};
}

declare const defaultSpeech:SpeechModule;
function newPet(presets: Presets): PetPackage {
  return {id:crypto.randomUUID(), name:ui('啾咪'), ...sugarPreset('chick',presets.chick.image), image:presets.chick.image, modules:[structuredClone(defaultSpeech)], plugins:[defaultSpeech.id], revision:0};
}

function setupMaker(presets: Presets, pet: PetPackage, update: (value: Partial<PetPackage>) => void) {
  const name = document.querySelector<HTMLInputElement>('#pet-name')!;
  const select = document.querySelector<HTMLSelectElement>('#preset')!;
  const upload = document.querySelector<HTMLInputElement>('#upload')!;
  const notice = document.querySelector<HTMLElement>('#notice')!;
  const controls = document.querySelector<HTMLElement>('#creation')!;
  controls.hidden = false;
  name.value = pet.name;
  for (const [key, preset] of Object.entries(presets)) select.add(new Option(ui(preset.label),key));
  select.add(new Option(ui('自定义 PNG'),'custom',false,false));
  select.options[select.length-1].disabled = true;
  document.addEventListener('jiumi-language', () => {
    for (const option of select.options) option.textContent = ui(presets[option.value]?.label ?? '自定义 PNG');
    name.setCustomValidity(name.value.trim() ? '' : ui('请输入名字'));
  });
  name.oninput = () => {
    const value = name.value.trim();
    name.setCustomValidity(value ? '' : ui('请输入名字'));
    if (value) update({name:value});
  };
  let request = 0;
  select.onchange = () => {
    ++request;
    upload.value = '';
    notice.textContent = '';
    update({...sugarPreset(select.value,presets[select.value].image),image:presets[select.value].image, appearance:{}});
  };
  upload.onchange = async () => {
    const file = upload.files?.[0];
    const version = ++request;
    if (!file) return;
    try {
      if (file.size > 3_000_000) throw new Error();
      const signature = new Uint8Array(await file.slice(0,8).arrayBuffer());
      if (signature.join() !== '137,80,78,71,13,10,26,10') throw new Error();
      const reader = new FileReader();
      const data = await new Promise<string>((resolve,reject) => {
        reader.onload = () => resolve(String(reader.result));
        reader.onerror = reject;
        reader.readAsDataURL(file);
      });
      const image = new Image();
      image.src = data;
      await image.decode();
      if (version !== request) return;
      select.value = 'custom';
      update({rig:undefined,image:data, appearance:{}});
      notice.textContent = '';
    } catch {
      if (version === request) notice.textContent = ui('请选择可打开的 PNG 图片，大小不超过 3 MB。');
    }
  };
}

type MotionClip = {label?:string, frames:string[], frameMs:number, loop:boolean};
function setupClips(read:()=>Record<string,MotionClip>, write:(clips:Record<string,MotionClip>)=>void, preview:(motion:string)=>void) {
  const field = <T extends HTMLElement>(id:string) => document.getElementById(id) as T;
  const motion = field<HTMLSelectElement>('clip-name');
  const files = field<HTMLInputElement>('clip-files');
  const duration = field<HTMLInputElement>('clip-duration');
  const loop = field<HTMLInputElement>('clip-loop');
  const status = field<HTMLElement>('clip-status');
  let sequence = 0;
  function refresh() {
    const clip = read()[motion.value];
    duration.value = String(clip?.frameMs ?? 160);
    loop.checked = clip?.loop ?? ['idle','held'].includes(motion.value);
    status.textContent = clip ? clip.frames.length + ui(' 帧') : ui('使用单图动效');
  }
  document.addEventListener('jiumi-language',refresh);
  motion.onchange = () => { ++sequence; files.value=''; refresh(); preview(motion.value); };
  field('new-clip').onclick=()=>{
    const input=field<HTMLInputElement>('new-clip-id');
    const id=input.value.trim();
    if(!/^[a-z][a-z0-9-]{0,47}$/.test(id) || id==='constructor'){
      status.textContent=ui('用小写字母开头，可包含数字、短横线，最多 48 个字符。');return;
    }
    if(!Array.from(motion.options).some(option=>option.value===id))motion.add(new Option(id,id));
    motion.value=id;
    ++sequence;refresh();files.value='';files.click();
  };
  files.onchange = async () => {
    const batch = Array.from(files.files ?? []).sort((a,b)=>a.name.localeCompare(b.name,undefined,{numeric:true}));
    if (!batch.length) return;
    const request = ++sequence;
    try {
      if(batch.length>32 || batch.reduce((n,f)=>n+f.size,0)>3_000_000) throw Error();
      const frames = await Promise.all(batch.map(async file=>{
        const bytes = new Uint8Array(await file.slice(0,8).arrayBuffer());
        if(bytes.join()!=='137,80,78,71,13,10,26,10') throw Error();
        const data = await new Promise<string>((resolve,reject)=>{
          const r=new FileReader(); r.onload=()=>resolve(String(r.result)); r.onerror=reject; r.readAsDataURL(file);
        });
        const img=new Image(); img.src=data; await img.decode(); return data;
      }));
      if(request!==sequence)return;
      const clips = {...read(),[motion.value]:{...read()[motion.value],frames,frameMs:Number(duration.value),loop:loop.checked}};
      if(Object.keys(clips).length>256 || JSON.stringify(clips).length>8_000_000)throw Error();
      write(clips); refresh(); preview(motion.value);
    } catch { if(request===sequence)status.textContent=ui('请使用有效 PNG，每组最多 32 帧、3 MB，全部动作最多 8 MB。'); }
  };
  function timing(){
    const clip=read()[motion.value];
    if(clip){write({...read(),[motion.value]:{...clip,frameMs:Number(duration.value),loop:loop.checked}});preview(motion.value);}
  }
  duration.onchange=loop.onchange=timing;
  field('clip-remove').onclick=()=>{++sequence; const clips={...read()};delete clips[motion.value];write(clips);files.value='';refresh();};
  refresh();
}

declare function checkModuleInstall(module:PetModule):Promise<void>;
function modulePanel(read:()=>PetPackage, write:(patch:Partial<PetPackage>)=>void){
  const list=document.getElementById('module-list')!;
  const file=document.querySelector<HTMLInputElement>('#module-file')!;
  const status=document.getElementById('module-status')!;
  function refresh(){
    list.replaceChildren();
    for(const mod of read().modules??[]){
      const item=document.createElement('div');
      item.dataset.moduleId=mod.id;
      const label=document.createElement('label');
      const toggle=document.createElement('input');
      toggle.type='checkbox';toggle.checked=read().plugins.includes(mod.id);
      toggle.onchange=()=>{
        const plugins=read().plugins.filter(id=>id!==mod.id);
        if(toggle.checked)plugins.push(mod.id);
        write({plugins});
      };
      label.append(toggle,ui(mod.name)+' v'+mod.version);
      const remove=document.createElement('button');
      remove.textContent=ui('移除');
      remove.onclick=()=>{
        const pet=read();
        write({modules:pet.modules?.filter(m=>m.id!==mod.id),plugins:pet.plugins.filter(id=>id!==mod.id)});
        refresh();
      };
      item.append(label,remove);list.append(item);
    }
  }
  document.addEventListener('jiumi-language',()=>{status.textContent='';refresh();});
  file.onchange=async()=>{
    try{
      const input=file.files?.[0];
      if(!input)return;
      if(input.size>100000)throw Error('插件包太大');
      const mod:PetModule=JSON.parse(await input.text());
      await checkModuleInstall(mod);
      const pet=read(), old=pet.modules?.find(m=>m.id===mod.id);
      if(old && (old.version>mod.version || (old.version===mod.version&&JSON.stringify(old)!==JSON.stringify(mod))))
        throw Error('此版本与已安装包冲突');
      const modules=[...(pet.modules??[]).filter(m=>m.id!==mod.id),mod];
      if(modules.length>8)throw Error('每只宠物最多安装八个插件');
      write({modules,plugins:[...new Set([...pet.plugins,mod.id])]});
      refresh();status.textContent=ui('已安装 ')+mod.name;
    }catch(error){status.textContent=error instanceof Error ? ui(error.message) : String(error);}
    finally{file.value='';}
  };
  refresh();
}
