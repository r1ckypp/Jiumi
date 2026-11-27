const assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs');
const runtime='skill/jiumi-pet/runtime/';
const pickup=JSON.parse(fs.readFileSync(runtime+'pickup.json'));
const make=vm.runInNewContext(['machines.js','player.js'].map(f=>fs.readFileSync(runtime+f,'utf8')).join('\n')+';createFeedback',{defaultPickup:pickup});
let now=2000000,last,finish,id=0,effects=0;
const engine=make({clock:()=>now,body:(intent,end)=>{last=intent;finish=end},effect:()=>effects++,
 rules:[{on:'pet.tap',effect:'particles'},{on:'timer.finished',intent:'celebrate'}]});
const send=(type,session='a',at=++now)=>engine.dispatch({v:1,type,source:'hook',session,at,id:String(++id)});
send('agent.started');assert.equal(last,'working');
send('agent.input_requested');assert.equal(last,'attention');const obsolete=finish;
send('pet.tap');assert.equal(last,'affection');assert.equal(effects,1);obsolete();assert.equal(last,'affection');
finish();assert.equal(last,'waiting');send('agent.resumed');assert.equal(last,'working');
send('agent.started','b');send('agent.completed');assert.equal(last,'celebrate');finish();assert.equal(last,'working');
send('agent.completed');assert.equal(last,'working');send('agent.input_requested','a',now-500);assert.equal(last,'working');
engine.setVisible(false);send('agent.input_requested','b');assert.equal(last,'silent');engine.setVisible(true);assert.equal(last,'waiting');
now+=310000;engine.tick();assert.equal(last,'idle');
send('timer.finished');assert.equal(last,'celebrate');finish();send('timer.finished','a',now-16000);assert.equal(last,'idle');

console.log('Event arbitration checks passed');

send('pet.grab');assert.equal(last,'held');
send('agent.input_requested','during-grab');assert.equal(last,'held');
assert.equal(engine.getState(),'waiting');assert.equal(engine.getInteraction(),'held');
send('pet.release');assert.equal(last,'landing');const oldLanding=finish;
send('pet.grab');oldLanding();assert.equal(engine.getInteraction(),'held');
send('pet.release');finish();assert.equal(last,'waiting');
send('pet.grab');send('pet.cancel');assert.equal(last,'waiting');
send('pet.grab');engine.setVisible(false);engine.setVisible(true);
assert.equal(engine.getInteraction(),'free');assert.equal(last,'waiting');
console.log('Grab, cancel, re-grab and landing recovery passed');

engine.dispose();send('pet.tap');assert.equal(last,'silent');

// These states and event names exist only in the test plugin.
const rest={kind:'state-machine',api:1,version:1,id:'rest',name:'Siesta',priority:10,
  enter:{'room.quiet':'dozing'},states:{
    dozing:{motion:'nap',resumeAt:'stretching',on:{'room.loud':'$base'}},
    stretching:{motion:'greet',after:'$resume'}
  }};
let displayed,onEnd;
const graph=make({machines:[rest,pickup],body:(motion,done)=>{displayed=motion;onEnd=done},effect(){}});
const emit=type=>graph.dispatch({v:1,id:String(++id),source:'demo',session:'one',at:Date.now(),type});
emit('room.quiet');assert.equal(graph.getInteraction(),'dozing');
emit('pet.grab');assert.equal(displayed,'held');
emit('agent.input_requested');emit('pet.release');onEnd();
assert.equal(graph.getInteraction(),'stretching');assert.equal(displayed,'greet');
onEnd();assert.equal(displayed,'waiting');
rest.states.dozing.resumeAt='$self';
emit('room.quiet');emit('pet.grab');emit('pet.cancel');assert.equal(displayed,'nap');
emit('pet.grab');emit('room.loud');emit('pet.release');onEnd();assert.equal(displayed,'waiting');
rest.states.dozing.resumeAt='$discard';
emit('room.quiet');emit('pet.grab');emit('pet.release');onEnd();assert.equal(displayed,'waiting');
console.log('PASS plugin-defined states, explicit resume target, self, discard and suspended exit');

const timers = new Map();
let timerId = 0, elapsed = 0;
const timedMake = vm.runInNewContext(['machines.js','player.js'].map(f=>fs.readFileSync(runtime+f,'utf8')).join('\n')+';createFeedback',{
  defaultPickup:pickup,
  setTimeout(fn,ms){timers.set(++timerId,{at:elapsed+ms,fn});return timerId},
  clearTimeout(id){timers.delete(id)}
});
function advance(ms){
  elapsed+=ms;
  for(const [id,t] of timers)if(t.at<=elapsed){timers.delete(id);t.fn();}
}
const typing=JSON.parse(fs.readFileSync('examples/modules/typing.json'));
const timed=timedMake({machines:[typing,pickup],body(){},effect(){},clock:()=>elapsed});
function input(type){timed.dispatch({v:1,id:String(++id),source:'test',type,at:elapsed});}
input('typing.stroke');advance(4500);input('typing.stroke');advance(4999);
assert.equal(timed.getInteraction(),'right');advance(1);
assert.equal(timed.getBodyIntent(),'idle');
typing.states.left.resumeAt='$self';
input('typing.stroke');input('pet.grab');advance(5000);
assert.equal(timed.getInteraction(),'held');input('pet.cancel');assert.equal(timed.getInteraction(),'free');
input('typing.stroke');timed.dispose();assert.equal(timers.size,0);
console.log('PASS renewable inactivity timeout, suspended expiration and disposal');
