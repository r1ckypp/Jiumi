interface PetAppearance {
  scale?: number;
  hue?: number;
  ears?: number;
  inner?: string;
  eyes?: string;
  nose?: string;
  motions?: Record<string, string>;
}

interface PetRig {
  kind:'sugar'|'humanoid';
  species?:string;
  style?:'knight'|'humanoid';
  layers?:Record<string,string>;
  poses?:Record<string,{duration:number,label?:string,joints:Record<string,number[]>}>;
}

interface PetPackage {
  defaultLanguage?:"en"|"zh-CN";
  rig?:PetRig;
  id: string;
  name: string;
  color: string;
  image: string;
  appearance?: PetAppearance;
  modules?: PetModule[];
  moduleState?: Record<string,number>;
  motionPools?: Record<string,string[]>;
  clips?: Record<string, MotionClip>;
  plugins: string[];
  revision: number;
}

interface PetEvent {
  v: 1;
  id: string;
  source: string;
  type: string;
  session?: string;
  summary?: string;
  at: number;
}

interface PetRule {
  id: string;
  version: number;
  name: string;
  on: string;
  effect?: 'particles';
  symbol?: string;
  intent?: 'attention' | 'affection' | 'celebrate';
}

interface SpeechModule { kind:"speech"; api:1; id:string; version:number; name:string; lines:string[]; minSeconds:number; maxSeconds:number; durationSeconds:number }
type PetModule = SpeechModule | WasmModule | StateMachineModule | SessionNoticeModule;

interface SessionNoticeModule {
  kind:"session-notice";
  api:1;
  id:string;
  name:string;
  version:number;
  show:string;
  clear:string[];
  title:string;
  action:"session.open";
}

interface StateMachineModule {
  kind:"state-machine";
  api:1;
  id:string;
  name:string;
  version:number;
  priority:number;
  menu?:Record<string,string>;
  enter:Record<string,string>;
  states:Record<string,{motion:string;on?:Record<string,string>;after?:string;resumeAt?:string;timeoutMs?:number}>;
}

interface WasmModule {
  api:1;
  id:string;
  version:number;
  name:string;
  events:string[];
  capabilities:('state'|'motion')[];
  wasm:string;
  sha256:string;
}
