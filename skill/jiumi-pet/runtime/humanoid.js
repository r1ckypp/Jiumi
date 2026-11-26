function drawKnight(part,pet){
  const steel='#a9c9d2', trim='#f9cb6b', cloak=rigFill(pet.color,'#567c90');
  const armored=pet.rig.style==='knight';
  if(armored)part('cape',79,68,'<path fill="'+cloak+'" d="M-18 -4 Q-22 26 -37 52 Q-8 62 18 49 L16 -5Z"/>');
  const torso=part('torso',80,74,'');
  for(const [i,side] of ['Left','Right'].entries()){
    const thigh=part('leg'+side,i?10:-11,28,'<path fill="#596978" d="M-6 -4 L7 -4 L7 17 Q0 21 -6 16Z"/>',torso);
    part('shin'+side,0,16,'<path fill="'+steel+'" d="M-7 -3 Q0 -8 7 -3 L7 12 L11 16 Q12 21 -8 19Z"/>',thigh);
  }
  part('plate',0,0,'<path fill="'+steel+'" d="M-20 -11 Q-1 -21 20 -11 L15 22 L0 33 L-15 23Z"/><path fill="'+cloak+'" d="M-9 -11 L8 -11 L8 24 L0 29 L-8 24Z"/><path fill="'+trim+'" stroke="none" d="M0 -4 L3 2 L8 4 L3 7 L0 14 L-3 7 L-8 4 L-3 2Z"/>',torso);
  for(const [i,side] of ['Left','Right'].entries()){
    const arm=part('arm'+side,i?21:-21,-6,'<path fill="'+steel+'" d="M-8 -3 Q0 -12 8 -3 L7 14 Q0 19 -7 14Z"/>',torso);
    const fore=part('forearm'+side,0,15,'<path fill="#8295a6" d="M-6 -3 L6 -3 L6 13 Q0 19 -6 13Z"/>',arm);
    if(i&&armored)part('blade',4,11,'<g transform="rotate(22)"><path fill="#d6ebef" d="M-3 -10 L-4 -35 L0 -44 L4 -36 L3 -10Z"/><path stroke="#ae7c39" d="M0 6 L0 -10 M-7 -10 L7 -10"/></g>',fore);
    else if(!i&&armored)part('shield',-2,9,'<path fill="'+cloak+'" d="M-14 -13 Q0 -18 13 -12 L11 4 Q7 14 0 20 Q-13 13 -14 4Z"/><path fill="'+trim+'" stroke="none" d="M0 -10 L3 -2 L9 1 L3 4 L0 12 L-3 4 L-9 1 L-3 -2Z"/>',fore);
  }
  if(!armored){
    part('head',0,-21,'<ellipse cy="-4" rx="21" ry="24" fill="#e5b28c"/><path fill="#513e3a" d="M-20 -4 Q-24 -29 0 -30 Q24 -29 22 -9 L12 -16 Q-1 -6 -20 -4Z"/><path d="M-7 -2 v2 M10 -2 v2 M0 9 q4 2 7 -1" fill="none"/>',torso);return;
  }
  const head=part('head',0,-21,'<path fill="'+steel+'" d="M-21 -9 Q-19 -27 0 -27 Q22 -26 23 -9 L21 9 L7 20 L-11 18 L-21 7Z"/><path fill="#3d5361" d="M-18 -4 Q1 -9 21 -5 L18 3 Q0 -1 -17 5Z"/><path fill="none" d="M3 7 L3 13 M9 5 L9 11"/>',torso);
  part('plume',-2,-23,'<path fill="#d6674d" d="M3 3 Q14 -20 -4 -22 Q-25 -24 -32 -6 Q-22 -11 -16 -6 Q-7 -4 3 -12Z"/>',head);
}
