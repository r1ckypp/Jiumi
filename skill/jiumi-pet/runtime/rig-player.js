// Local joint origins are nested so a child inherits its parent's transform.
function rigPicture(pet){
  const rig=pet.rig, sugar=rig?.kind==='sugar';
  if(!sugar && rig?.kind!=='humanoid')return null;
  const holder=document.createElement('div');
  const svg=document.createElementNS('http://www.w3.org/2000/svg','svg');
  svg.setAttribute('viewBox','0 0 160 160');
  svg.style.cssText='width:100%;height:100%;overflow:visible';
  holder.append(svg);
  const nodes=new Map(), namespace=svg.namespaceURI;
  function part(name,x,y,art,parent=svg){
    const anchor=document.createElementNS(namespace,'g'),joint=document.createElementNS(namespace,'g');
    anchor.setAttribute('transform','translate('+x+' '+y+')');
    joint.dataset.joint=name;
    anchor.append(joint);parent.append(anchor);nodes.set(name,joint);
    const skin=rig.layers?.[name];
    if(typeof skin==='string' && skin.startsWith('data:image/png;base64,')){
      const image=document.createElementNS(namespace,'image');
      // All replacement textures use the same 160-square joint-centred artboard.
      for(const [k,v] of Object.entries({x:-80,y:-80,width:160,height:160,href:skin}))image.setAttribute(k,v);
      joint.append(image);
    }else joint.innerHTML=art;
    return joint;
  }
  svg.setAttribute('stroke',sugar?'#694426':'#2c3544');
  svg.setAttribute('stroke-width','3.2');
  svg.setAttribute('stroke-linejoin','round');svg.setAttribute('stroke-linecap','round');
  if(sugar)drawSugar(part,pet);
  else drawKnight(part,pet);
  let running=[];
  holder.stopPose=()=>{for(const animation of running)animation.cancel();running=[];};
  holder.pose=(name,duration)=>{
    const held=name==='held', land=name==='landing', walk=['walk','run'].includes(name);
    const sleepy=name==='nap', wave=['pet','greet','hop','swing'].includes(name);
    function turn(key,angles){
      const node=nodes.get(key);if(!node)return;
      running.push(node.animate(angles.map(a=>({transform:'rotate('+a+'deg)'})),{duration,easing:'ease-in-out',fill:'both'}));
    }
    const custom=rig.poses?.[name];
    if(custom){for(const [key,angles] of Object.entries(custom.joints))turn(key,angles);return;}
    for(const [i,side] of ['Left','Right'].entries()){
      const sign=i?1:-1;
      const swing=held?[12,-25,32,-20,12]:walk?[-26,28,-26]:land?[22,-18,5,0]:[0,0];
      turn('leg'+side,swing.map(a=>a*sign));
      turn('shin'+side,held?[12,48,8,42,12]:walk?[5,i?35:55,5]:land?[6,55,12,0]:[0,0]);
      const arm=held?[20,60,24,68,20]:wave?[0,70,40,70,0]:walk?[22,-25,22]:land?[40,6,25,0]:sleepy?[3,12,3]:[0,4,0];
      turn('arm'+side,arm.map(a=>-a*sign));
      turn('forearm'+side,(held?[18,58,22,18]:wave?[0,65,25,0]:land?[15,48,0]:[2,8,2]).map(a=>a*sign));
      turn('ear'+side,(held?[8,-15,12,-8,8]:land?[-15,14,-6,0]:[0,4,0]).map(a=>a*sign));
    }
    turn('head',held?[-6,7,-6]:land?[-8,10,0]:sleepy?[0,10,6]:[0,2,0]);
    turn('plume',held?[-15,18,-15]:land?[15,-18,6,0]:[-3,4,-3]);
    const eyes=nodes.get('eyes');
    if(eyes){
      const heights=held||sleepy?[.12,.08,.12]:land?[.12,.1,1]:[1,1,.1,1,1];
      running.push(eyes.animate(heights.map((v,i)=>({transform:'scaleY('+v+')',offset:heights.length===5?[0,.78,.82,.86,1][i]:i/(heights.length-1)})),{duration,fill:'both'}));
    }
  };
  holder.dataset.performer=rig.kind;
  return holder;
}
function rigFill(color,fallback){
  return /^#[a-f\d]{6}$/i.test(color)?color:fallback;
}
