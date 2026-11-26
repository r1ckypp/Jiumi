// AssemblyScript uses TypeScript syntax with explicit WebAssembly numeric types.
// The host passes the subscription index for each event in the manifest.
@external("pet", "save") declare function save(value:f64):void;
@external("pet", "play") declare function play(motion:i32):void;

export function step(event:i32, now:f64, deadline:f64):void {
  if (event == 1 && deadline == 0) {
    save(now + 25 * 60 * 1000);
    play(1);
  } else if (deadline > 0 && now >= deadline && (event == 0 || event == 2 || event == 3)) {
    save(0);
    play(2);
  }
}
