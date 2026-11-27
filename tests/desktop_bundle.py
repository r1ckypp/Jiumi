"""Launch the packaged native host with no scripting runtimes on its search path."""
import json
import os
import plistlib
from pathlib import Path
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory() as tmp:
    os.environ["PET_HOME"]=tmp
    sys.path.insert(0,"skill/jiumi-pet")
    import pet
    role=pet.create("泡泡","#ffcf67",language="en")
    pid=role["id"]
    data=pet.read(pid)
    module=json.loads(Path("examples/modules/focus-timer.json").read_text())
    data.update(modules=[module],plugins=[module["id"]])
    pet.store(data)
    app=Path(pet.desktop_app(pid,tmp))
    info=plistlib.loads((app/"Contents/Info.plist").read_bytes())
    assert data["defaultLanguage"]==info["JiumiDefaultLanguage"]=="en"
    assert app.name=="Jiumi.app" and info["CFBundleName"]==info["CFBundleDisplayName"]=="Jiumi"
    assert info["CFBundleIdentifier"]=="studio.jiumi.pet."+pid and pet.read(pid)["name"]=="泡泡"
    subprocess.run(["codesign","--verify",str(app)],check=True)
    binary=app/"Contents/MacOS/Jiumi"
    process=subprocess.Popen([str(binary)],stdin=subprocess.PIPE,text=True,env={**os.environ,"PATH":"/nonexistent"})
    try:
        event={"v":1,"id":"job","source":"test","session":"desktop","type":"agent.started","at":int(time.time()*1000)}
        process.stdin.write(json.dumps(event)+"\n")
        process.stdin.flush()
        for _ in range(160):
            if pet.read(pid).get("moduleState",{}).get("focus-timer",0)>event["at"]:break
            if process.poll() is not None:raise RuntimeError("桌宠提前退出")
            time.sleep(.1)
        else:raise RuntimeError("桌宠未持久化收到的计时事件")
    finally:
        process.terminate()
        process.wait(timeout=5)
    print("PASS standalone macOS app, WebKit module, native event and durable progress")
