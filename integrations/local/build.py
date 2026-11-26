"""Package the current offline Skill as an installable local marketplace."""
import base64
import sys
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[2]
import argparse

parser=argparse.ArgumentParser()
parser.add_argument("--official-assets",type=Path)
parser.add_argument("--official-guide",type=Path)
parser.add_argument("--output",type=Path,default=root/"dist")
args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
source=root/"skill/jiumi-pet"
sys.path.insert(0, str(source))
from preview_page import render_preview

presets = {}
if args.official_assets:
    names = {"chick":"方糖小鸡","pig":"蓝色小猪","bunny":"兔子","cat":"猫","cow":"奶牛","elephant":"大象"}
    for animal, label in names.items():
        image = (args.official_assets / (animal + ".png")).read_bytes()
        presets[animal] = {"label":label, "image":"data:image/png;base64," + base64.b64encode(image).decode()}
maker = args.output / "maker.html"
maker.write_text(render_preview(presets=presets))
skill_zip=args.output/"jiumi-pet-skill.zip"
with ZipFile(skill_zip,"w",ZIP_DEFLATED) as package:
    for path in sorted([*source.glob("*.py"),*source.glob("*.md"),*(source/"runtime").glob("*")]):
        package.write(args.official_guide if path.name=="SKILL.md" and args.official_guide else path,"jiumi-pet/"+str(path.relative_to(source)))
    package.write(root/"examples/modules/focus-timer.json","jiumi-pet/examples/focus-timer.json")
    package.write(source/"runtime/pickup.json","jiumi-pet/examples/pickup.json")
    package.write(root/"examples/modules/agent-confirm.json","jiumi-pet/examples/agent-confirm.json")
    for path in sorted((source/"references").glob("*.md")):
        package.write(path,"jiumi-pet/references/"+path.name)
    package.write(maker,"jiumi-pet/maker.html")
    package.write(root/"docs/spec/contracts.schema.json","jiumi-pet/contracts.schema.json")
    package.write(root/"LICENSE", "jiumi-pet/LICENSE")
    translation=(root/"docs/zh-CN/LICENSE.zh-CN.md").read_text().replace("](../../LICENSE)","](LICENSE)")
    package.writestr("jiumi-pet/LICENSE.zh-CN.md",translation)
    for suffix in ("", ".zh-CN"):
        package.write(root/"docs/spec"/("host-capabilities"+suffix+".md"),"jiumi-pet/host-capabilities"+suffix+".md")
        guide=(root/"docs/spec"/("plugin-sdk"+suffix+".md")).read_text().replace("](plugin-sdk", "](STATE-MACHINES")
        package.writestr("jiumi-pet/STATE-MACHINES"+suffix+".md",guide)
        document = (root/"docs/spec"/("event-feedback"+suffix+".md")).read_text()
        document = document.replace("](event-feedback", "](EVENT-SPEC").replace("](plugin-sdk", "](STATE-MACHINES")
        package.writestr("jiumi-pet/EVENT-SPEC"+suffix+".md", document)
    package.write(root/"examples/plugins/tap-confetti.json","jiumi-pet/examples/tap-confetti.json")
    if args.official_assets:
        for image in sorted(args.official_assets.glob("*.png")):
            package.write(image,"jiumi-pet/animals/"+image.name)
output=args.output/"jiumi-local.zip"
manifest = {"name":"jiumi-local","version":"1.7.1","description":"创建方糖桌宠，离线预览和导出 HTML。","skills":"./skills/"}
market = {"name":"jiumi-studio","interface":{"displayName":"啾咪工作室"},"plugins":[{"name":"jiumi-local","source":{"source":"local","path":"./plugins/jiumi-local"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Productivity"}]}
with ZipFile(output,"w",ZIP_DEFLATED) as package, ZipFile(skill_zip) as skills:
    package.writestr(".agents/plugins/marketplace.json",json.dumps(market,ensure_ascii=False))
    package.writestr("plugins/jiumi-local/.codex-plugin/plugin.json",json.dumps(manifest,ensure_ascii=False))
    for name in skills.namelist():
        package.writestr("plugins/jiumi-local/skills/"+name,skills.read(name))
