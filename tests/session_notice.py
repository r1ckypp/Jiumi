"""Import a notice plugin, export to file and interact with it while disconnected."""
import argparse
from pathlib import Path
import tempfile
from playwright.sync_api import sync_playwright

parser=argparse.ArgumentParser()
parser.add_argument("--output",type=Path)
parser.add_argument("--image",type=Path)
args=parser.parse_args()
with tempfile.TemporaryDirectory() as tmp,sync_playwright() as pw:
    page=pw.chromium.launch(channel="chrome").new_context(offline=True).new_page()
    errors=[]
    page.on("pageerror",lambda error:errors.append(str(error)))
    page.goto(Path("dist/maker.html").resolve().as_uri())
    assert page.locator("html").get_attribute("lang") == "en"
    page.select_option("#language", "zh-CN")
    if args.image:
        page.set_input_files("#upload",args.image)
        page.wait_for_function("current().image.startsWith('data:image/png')")
    page.fill("#pet-name","蓝色小猪")
    page.locator("#module-panel summary").click()
    page.set_input_files("#module-file","examples/modules/agent-confirm.json")
    page.get_by_text("已安装 Agent 等你确认").wait_for()
    with page.expect_download() as download: page.click("#confirm")
    path=args.output or Path(tmp)/"confirmation.html"
    download.value.save_as(path)
    page.goto(path.resolve().as_uri())
    page.get_by_role("button",name="试用会话提醒").click()
    panel=page.locator("aside")
    assert "示例会话" in panel.inner_text()
    assert not panel.get_by_role("button").count()
    before=panel.bounding_box()
    stage=page.locator("#stage")
    box=stage.bounding_box()
    x,y=box["x"]+box["width"]/2,box["y"]+box["height"]/2
    page.mouse.move(x,y);page.mouse.down()
    page.wait_for_function("stage.dataset.interaction==='held'")
    page.mouse.move(x+65,y-30)
    assert abs(panel.bounding_box()["x"]-before["x"]-65)<2
    page.mouse.up()
    page.wait_for_function("stage.dataset.interaction==='free'")
    assert "示例会话" in panel.inner_text()
    page.get_by_role("button",name="结束示例提醒").click()
    assert panel.is_hidden()
    # A capable embedding handles a scoped action, including concurrent sources.
    page.evaluate("""()=>{window.opened=[];mountPet(stage,pet,rules,{session:(method,target)=>{
      if(method==='open')opened.push(target);return target.source==='a';
    }});}""")
    def emit(source,kind):
        page.evaluate("""([source,type])=>stage.feedback.dispatch({v:1,id:crypto.randomUUID(),
          source,type,session:'thread-one',at:Date.now(),summary:'请检查预览'})""",[source,kind])
    emit("a","agent.input_requested");emit("b","agent.input_requested")
    assert not panel.get_by_role("button").count()
    emit("b","agent.completed")
    panel.get_by_role("button",name="回到会话").click()
    assert page.evaluate("opened")==[{"source":"a","session":"thread-one"}]
    assert panel.is_visible()
    emit("a","agent.resumed")
    assert panel.is_hidden() and not errors,errors
    print("PASS offline plugin import, export, pointer drag, landing, scoped return and resolution")
