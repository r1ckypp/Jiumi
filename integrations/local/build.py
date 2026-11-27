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

def build_skill(skill_name):
    directory = root / "skill" / skill_name
    archive = args.output / f"{skill_name}-skill.zip"
    guide = (directory / "SKILL.md").read_text()
    references = directory / "references"
    if args.official_guide and skill_name == "jiumi-pet":
        guide = args.official_guide.read_text()
        # Existing downstream Chinese guides refer to the former bilingual layout.
        if "references/workflows.zh-CN.md" in guide:
            references = root / "skill/jiumi-pet-zh/references"
            for page in references.glob("*.md"):
                guide = guide.replace(f"references/{page.stem}.zh-CN.md", f"references/{page.name}")

    with ZipFile(archive, "w", ZIP_DEFLATED) as package:
        package.writestr(f"{skill_name}/SKILL.md", guide)
        for path in sorted(references.glob("*.md")):
            package.write(path, f"{skill_name}/references/{path.name}")
        for path in sorted([*source.glob("*.py"), *(source / "runtime").glob("*")]):
            package.write(path, f"{skill_name}/{path.relative_to(source)}")
        for path in [root / "examples/modules/focus-timer.json", source / "runtime/pickup.json", root / "examples/modules/typing.json",
                     root / "examples/modules/feed.json", root / "examples/modules/agent-confirm.json", root / "examples/plugins/tap-confetti.json"]:
            package.write(path, f"{skill_name}/examples/{path.name}")
        package.write(maker, f"{skill_name}/maker.html")
        package.write(root / "docs/spec/contracts.schema.json", f"{skill_name}/contracts.schema.json")
        package.write(root / "LICENSE", f"{skill_name}/LICENSE")
        if skill_name == "jiumi-pet-zh":
            translation = (root / "docs/zh-CN/LICENSE.zh-CN.md").read_text().replace("](../../LICENSE)", "](LICENSE)")
            package.writestr(f"{skill_name}/LICENSE.zh-CN.md", translation)
        for original, packaged in [("event-feedback.md", "EVENT-SPEC.md"),
                                       ("plugin-sdk.md", "STATE-MACHINES.md"),
                                       ("host-capabilities.md", "host-capabilities.md")]:
            spec = (root / "docs/spec" / original).read_text().replace("](plugin-sdk.md)", "](STATE-MACHINES.md)")
            package.writestr(f"{skill_name}/{packaged}", spec)
        if args.official_assets:
            for image in sorted(args.official_assets.glob("*.png")):
                package.write(image, f"{skill_name}/animals/{image.name}")
    return archive


def build_plugin(skill_zip, plugin_name, description, display_name):
    output = args.output / f"{plugin_name}.zip"
    manifest = {"name":plugin_name,"version":"1.7.1","description":description,"skills":"./skills/"}
    market = {"name":"jiumi-studio","interface":{"displayName":display_name},"plugins":[{"name":plugin_name,"source":{"source":"local","path":f"./plugins/{plugin_name}"},"policy":{"installation":"AVAILABLE","authentication":"ON_INSTALL"},"category":"Productivity"}]}
    with ZipFile(output,"w",ZIP_DEFLATED) as package, ZipFile(skill_zip) as skills:
        package.writestr(".agents/plugins/marketplace.json",json.dumps(market,ensure_ascii=False))
        package.writestr(f"plugins/{plugin_name}/.codex-plugin/plugin.json",json.dumps(manifest,ensure_ascii=False))
        for name in skills.namelist():
            package.writestr(f"plugins/{plugin_name}/skills/"+name,skills.read(name))


build_plugin(build_skill("jiumi-pet"), "jiumi-local", "Create, preview and export a desktop pet locally.", "Jiumi Studio")
build_plugin(build_skill("jiumi-pet-zh"), "jiumi-local-zh", "创建方糖桌宠，在本机预览并导出 HTML。", "啾咪工作室")
