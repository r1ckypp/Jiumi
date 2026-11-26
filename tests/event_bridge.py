"""Replay real hook payload shapes through stdin, IPC and the offline player."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
from playwright.sync_api import sync_playwright

with tempfile.TemporaryDirectory() as temp:
    os.environ["PET_HOME"]=temp
    sys.path.insert(0,"skill/jiumi-pet")
    import agent_events
    import pet
    role=pet.create("泡泡","#ffcf67")
    data=pet.read(role["id"])
    data.update(modules=[json.loads(Path("examples/modules/focus-timer.json").read_text())],plugins=["focus-timer"])
    pet.store(data)
    role["preview"]=pet.designer(role["id"])
    path=Path(agent_events.address(role["id"]))
    try:
        with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as receiver,sync_playwright() as pw:
            receiver.bind(str(path))
            receiver.settimeout(3)
            page=pw.chromium.launch(channel="chrome").new_context(offline=True).new_page()
            page.goto(Path(role["preview"]).as_uri())
            for hook,state in [("UserPromptSubmit","working"),("PermissionRequest","waiting"),("PreToolUse","working"),("Stop","idle")]:
                payload={"hook_event_name":hook,"session_id":"fixture","message":"PRIVATE"}
                subprocess.run([sys.executable,"skill/jiumi-pet/agent_events.py","claude",role["id"]],input=json.dumps(payload),text=True,check=True)
                raw=receiver.recv(4096)
                assert b"PRIVATE" not in raw
                page.evaluate("event=>stage.feedback.dispatch(event)",json.loads(raw))
                assert page.locator("#stage").get_attribute("data-state")==state
                if hook=="UserPromptSubmit":page.wait_for_function("current().moduleState['focus-timer']>Date.now()")
                if state=="waiting":
                    page.locator("#stage").click()
                    page.wait_for_function("stage.dataset.motion==='expect'")
            page.wait_for_function("stage.dataset.motion==='idle'")
    finally:
        path.unlink(missing_ok=True)
print("PASS hook adapter, Unix datagram, offline renderer and interrupt recovery")
