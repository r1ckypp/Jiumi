"""Exercise a real compiled plugin in an offline browser, including wake and disposal."""
import json
from pathlib import Path
import tempfile

from playwright.sync_api import sync_playwright

manifest=Path("examples/modules/focus-timer.json").resolve()
with sync_playwright() as pw, tempfile.TemporaryDirectory() as temp:
    page=pw.chromium.launch(channel="chrome").new_context(offline=True).new_page()
    page.goto(Path("dist/maker.html").resolve().as_uri())
    assert page.locator("html").get_attribute("lang") == "en"
    page.select_option("#language", "zh-CN")
    page.locator("#module-panel summary").click()
    page.set_input_files("#module-file",manifest)
    page.wait_for_function("document.querySelector('#module-list input')?.checked")
    def start():
        page.evaluate("""()=>stage.feedback.dispatch({v:1,id:crypto.randomUUID(),source:'fixture',type:'agent.started',session:'fixture',at:Date.now()})""")
    start()
    page.wait_for_function("current().moduleState['focus-timer']>Date.now()")
    deadline=page.evaluate("current().moduleState['focus-timer']")
    page.locator("#module-list input").uncheck()
    page.locator("#module-list input").check()
    assert page.evaluate("current().moduleState['focus-timer']")==deadline
    bad=json.loads(manifest.read_text())
    bad["capabilities"].append("network")
    page.set_input_files("#module-file",{"name":"bad.json","mimeType":"application/json","buffer":json.dumps(bad).encode()})
    page.wait_for_function("document.querySelector('#module-status').textContent.includes('不兼容')")
    assert page.locator("#module-list input").is_checked()
    # Simulate a worker that starts but cannot answer during an update.
    page.evaluate("()=>{window.HealthyWorker=window.Worker;window.Worker=class {postMessage(){} terminate(){}}}")
    updated=json.loads(manifest.read_text())
    updated["version"]+=1
    page.set_input_files("#module-file",{"name":"update.json","mimeType":"application/json","buffer":json.dumps(updated).encode()})
    page.wait_for_function("document.querySelector('#module-status').textContent.includes('超时')")
    assert page.evaluate("current().modules[0].version")==1
    page.evaluate("()=>{window.Worker=window.HealthyWorker}")
    with page.expect_download() as result:
        page.click("#confirm")
    path=Path(temp)/"pet.html"
    result.value.save_as(path)
    page.goto(path.as_uri())
    assert page.evaluate("pet.moduleState['focus-timer']")==deadline
    page.evaluate("stage.feedback.setVisible(false)")
    page.evaluate("(deadline)=>{Date.now=()=>deadline+1;stage.feedback.setVisible(true)}",deadline)
    page.wait_for_function("pet.moduleState['focus-timer']===0")
    page.wait_for_timeout(1500)
    page.evaluate("stage.feedback.setVisible(true)")
    assert page.locator("#stage").get_attribute("data-motion")!="greet"
    with page.expect_download() as result:
        page.click("#save-progress")
    assert json.loads(Path(result.value.path()).read_text())["moduleState"]["focus-timer"]==0
    page.goto(Path("dist/maker.html").resolve().as_uri())
    page.locator("#module-panel summary").click()
    page.set_input_files("#module-file",manifest)
    page.get_by_role("button",name="移除",exact=True).click()
    start()
    assert page.evaluate("current().plugins.length===0 && current().modules.length===0")
    print("PASS offline module installation, denied capability, state, wake, single settlement, export and removal")
    # A new graph can be imported, interrupted by pickup and restored after export.
    graph={"kind":"state-machine","api":1,"version":1,"id":"quiet","name":"Quiet","priority":10,
           "enter":{"room.quiet":"doze"},"states":{"doze":{"motion":"nap","resumeAt":"wake"},
           "wake":{"motion":"greet","after":"$resume"}}}
    page.set_input_files("#module-file",{"name":"quiet.json","mimeType":"application/json","buffer":json.dumps(graph).encode()})
    page.wait_for_function("current().plugins.includes('quiet')")
    with page.expect_download() as result:
        page.click("#confirm")
    result.value.save_as(path)
    page.goto(path.as_uri())
    def emit(event):
        page.evaluate("type=>stage.feedback.dispatch({v:1,id:crypto.randomUUID(),source:'demo',session:'demo',at:Date.now(),type})",event)
    def state(value):
        page.wait_for_function("value=>stage.feedback.getInteraction()===value",arg=value)
    emit("room.quiet"); state("doze")
    emit("pet.grab"); state("held")
    emit("pet.release"); state("landing")
    state("wake"); state("free")
    print("PASS imported custom state machine resumes its declared recovery state in the exported offline pet")
    page.goto(Path("dist/maker.html").resolve().as_uri())
    page.locator("#module-panel summary").click()
    page.set_input_files("#module-file",Path("examples/modules/feed.json"))
    menu=page.get_by_label("互动",exact=True)
    menu.select_option("menu.feed.bite")
    state("eating")
    state("free")
    page.locator("#module-list input").uncheck()
    assert menu.count()==0
    page.locator("#module-list input").check()
    with page.expect_download() as result:
        page.click("#confirm")
    result.value.save_as(path)
    page.goto(path.as_uri())
    menu.select_option("menu.feed.bite")
    state("eating")
    emit("pet.grab"); state("held")
    emit("pet.release"); state("landing")
    state("free")
    print("PASS menu installation, disabling, export and interrupted feeding")
