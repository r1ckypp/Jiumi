"""Exercise the native host page offline with an installed interaction, timer and notice."""
import json
import os
from pathlib import Path
import sys
import tempfile

from playwright.sync_api import sync_playwright

with tempfile.TemporaryDirectory() as home, sync_playwright() as pw:
    os.environ["PET_HOME"] = home
    sys.path.insert(0, str(Path("skill/jiumi-pet").resolve()))
    import pet

    modules = [json.loads(Path(f"examples/modules/{name}.json").read_text())
               for name in ("feed", "focus-timer", "agent-confirm")]
    role = pet.create("测试", modules=modules)
    browser = pw.chromium.launch(channel="chrome")
    page = browser.new_context(offline=True).new_page()
    page.add_init_script("window.webkit={messageHandlers:{petSession:{postMessage:async()=>false}}}")
    page.goto(pet.window_page(role["id"]).as_uri())
    def run(script):
        return page.evaluate(script)
    def emit(event):
        page.evaluate("type=>stage.feedback.dispatch({v:1,id:crypto.randomUUID(),source:'test',session:'one',type,at:Date.now()})", event)
    emit("agent.started")
    page.wait_for_function("pet.moduleState['focus-timer']>0")
    deadline = run("pet.moduleState['focus-timer']")
    emit("agent.input_requested")
    assert run("stage.feedback.selectMenu('menu.feed.bite')")
    assert run("stage.feedback.setPlugin('feed',false)")
    assert not run("stage.feedback.selectMenu('menu.feed.bite')")
    assert run("stage.feedback.getInteraction()==='free' && stage.feedback.getState()==='waiting'")
    assert page.locator("aside").is_visible()
    assert run("pet.moduleState['focus-timer']")==deadline
    assert run("stage.feedback.setPlugin('feed',true)")
    assert run("stage.feedback.selectMenu('menu.feed.bite')")
    assert run("stage.feedback.setPlugin('agent-confirm',false)")
    assert not page.locator("aside").is_visible()
    assert not run("stage.feedback.setPlugin('unknown',true)")
    browser.close()
    print("PASS native plugin changes preserve timer and session, interrupt disabled actions and update menus")
