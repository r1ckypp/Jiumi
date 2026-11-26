"""Exercise the distributed file directly with browser networking disabled."""
import json
from pathlib import Path
import sys
import tempfile

from playwright.sync_api import sync_playwright

maker = Path(sys.argv[1] if len(sys.argv)>1 else "dist/maker.html").resolve()
with tempfile.TemporaryDirectory() as tmp, sync_playwright() as pw:
    context = pw.chromium.launch(channel="chrome").new_context(offline=True)
    page = context.new_page()
    errors, remote = [], []
    page.on("pageerror", lambda err: errors.append(str(err)))
    page.on("request", lambda req: remote.append(req.url) if req.url.startswith(("http:", "https:")) else None)
    page.goto(maker.as_uri())
    assert page.locator("html").get_attribute("lang") == "en"
    page.select_option("#language", "zh-CN")
    page.select_option("#preset", "pig")
    page.fill("#pet-name", "泡泡<蓝>")
    page.select_option("#language", "en")
    assert page.input_value("#pet-name") == "泡泡<蓝>" and page.input_value("#preset") == "pig"
    assert page.locator("#confirm").inner_text() == "Export pet HTML"
    page.fill("#scale", "84")
    page.fill("#hue", "32")
    def export(selector, filename):
        with page.expect_download() as result:
            page.click(selector)
        target = Path(tmp) / filename
        result.value.save_as(target)
        return target
    pet = json.loads(export("#export","pet.json").read_text())
    assert pet["name"] == "泡泡<蓝>" and pet["appearance"] == {"scale":84,"hue":32}
    import base64
    png = base64.b64decode(pet["image"].split(",")[1])
    page.locator("#clips summary").click()
    blink=page.evaluate("bluePig(true)")
    closed=base64.b64decode(blink.split(",")[1])
    page.set_input_files("#clip-files",[{"name":name,"mimeType":"image/png","buffer":art} for name,art in [("01.png",png),("02.png",closed)]])
    page.wait_for_function("document.querySelector('#clip-status').textContent==='2 frames'")
    revised = json.loads(export("#export","revised.json").read_text())
    assert revised["id"] == pet["id"] and revised["clips"]["idle"]["frames"] == [pet["image"],blink]
    html = export("#confirm", "pet.html")
    page.goto(html.as_uri())
    assert page.locator("html").get_attribute("lang") == "en"
    assert page.locator("#name").inner_text() == pet["name"]
    assert page.locator("#stage img:visible").evaluate("e=>e.naturalWidth>0 && e.style.filter==='hue-rotate(32deg)'")
    page.wait_for_function("src=>document.querySelector('#stage img:not([hidden])').src===src",arg=blink)
    assert page.locator("#name").is_hidden()
    page.locator("#show-name").check()
    assert page.locator("#name").is_visible()
    rect=page.locator("#stage").bounding_box()
    x,y=rect["x"]+rect["width"]/2,rect["y"]+rect["height"]/2
    page.mouse.move(x,y)
    page.mouse.down()
    page.wait_for_selector('[data-pet-touch="held"]')
    assert page.locator(".jiumi-hand").inner_text()=="🤏"
    assert page.locator("#stage").get_attribute("data-motion")=="held"
    page.mouse.move(x+30,y+20)
    page.mouse.up()
    assert page.locator("#stage").bounding_box()["x"]>rect["x"]+25
    assert page.inner_text("#feedback")==""
    assert page.locator("#stage").get_attribute("data-motion")=="landing"
    page.wait_for_function("stage.dataset.interaction==='free'")
    page.click("#stage")
    assert page.locator(".jiumi-hand").inner_text()=="🫳"
    assert "1" in page.inner_text("#feedback")
    assert page.locator("#stage").get_attribute("data-motion")=="pet"
    page.wait_for_function("document.querySelector('#stage').dataset.motion==='idle'")
    page.goto(maker.as_uri())
    import base64
    png = base64.b64decode(pet["image"].split(",")[1])
    page.set_input_files("#upload", {"name":"custom.png","mimeType":"image/png","buffer":png})
    page.wait_for_function("document.querySelector('#preset').value === 'custom'")
    imported = json.loads(export("#export","custom.json").read_text())
    assert imported["image"] == pet["image"] and imported["id"] != pet["id"]
    assert not errors and not remote, (errors, remote)
    print("PASS offline maker, PNG import, identity, appearance and interactive HTML export")
