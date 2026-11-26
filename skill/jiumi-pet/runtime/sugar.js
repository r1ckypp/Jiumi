function drawSugar(part,pet){
  const species=pet.rig.species,color=rigFill(pet.color,'#fac763');
  const chick=species==='chick', pig=species==='pig';
  const paw=chick?'#f7a245':color;
  for(const [i,side] of ['Left','Right'].entries()){
    part('leg'+side,i?106:59,119,'<path fill="'+paw+'" d="M-8 -4 Q-14 10 -9 18 Q-2 25 9 17 L10 -4Z"/>');
  }
  part('body',80,84,'<path fill="'+color+'" d="M-51 -28 Q-50 -49 -25 -52 L25 -51 Q50 -48 52 -23 L52 25 Q49 47 22 50 L-22 50 Q-51 48 -52 26Z"/><path fill="#fff" opacity=".32" stroke="none" d="M-42 -27 Q-39 -44 -17 -44 L18 -43 Q-5 -37 -23 -34Z"/><path fill="#694426" opacity=".09" stroke="none" d="M30 -44 Q49 -38 49 -19 L49 24 Q48 46 20 46 Q32 36 32 18Z"/>');
  for(const [i,side] of ['Left','Right'].entries()){
    let ear=chick?'M-2 4 Q-23 -7 -14 -24 Q1 -34 8 -17 Q11 -8 6 4Z':species==='bunny'?'M-9 7 Q-17 -42 -4 -46 Q11 -49 10 5Z':species==='elephant'?'M-2 -4 Q-33 -18 -28 15 Q-20 39 4 18Z':'M-12 10 Q-19 -24 -11 -24 Q11 -21 13 0Z';
    const x=chick?(i?84:74):(i?113:49);
    part('ear'+side,x,chick?36:47,'<g transform="scale('+(i?-1:1)+' 1)"><path fill="'+color+'" d="'+ear+'"/>'+(!chick && species!=='elephant'?'<path fill="#efb7ae" stroke="none" d="M-10 1 L-12 -15 Q0 -13 6 -1Z"/>':'')+'</g>');
    part('arm'+side,i?123:39,87,'<path fill="'+color+'" d="M-5 -2 Q-15 4 -12 18 Q-7 27 2 21 Q10 15 9 3Z"/>');
  }
  part('eyes',86,74,'<g fill="#503523" stroke="none"><ellipse cx="-16" rx="4" ry="6"/><ellipse cx="22" rx="4" ry="6"/><g fill="white"><circle cx="-15" cy="-2" r="1.3"/><circle cx="23" cy="-2" r="1.3"/></g></g>');
  const muzzle=pig||species==='cow'?'<ellipse rx="17" ry="10" fill="#f5bac1"/><g fill="#935963" stroke="none"><ellipse cx="-6" rx="2" ry="4"/><ellipse cx="6" rx="2" ry="4"/></g>':chick?'<path fill="#ffa63b" d="M-10 -1 Q0 -14 12 -1 Q3 15 -3 9Z"/>':species==='elephant'?'<path fill="'+color+'" d="M-6 -2 Q-8 28 6 27 Q19 24 13 15 Q7 22 6 -1"/>':'<path fill="#e7a5a2" d="M-5 -3 Q0 -6 6 -3 Q3 4 0 4Z"/>';
  part('muzzle',92,91,muzzle);
  if(species==='cow')part('spots',65,50,'<path fill="#614e45" stroke="none" d="M-12 0 Q-5 -11 4 -6 Q15 1 4 6 Q-6 13 -12 0Z"/>');
}

