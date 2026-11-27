from portable import SUGAR_COLORS, validate_module, validate_portable
from preview_page import player_source, render_preview
import argparse
import base64
import hashlib
import json
import os
import re
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
import webbrowser
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
LEGACY_DATA = Path.home()/"Library/Application Support/PetStudio/client"
DEFAULT_DATA = LEGACY_DATA
if sys.platform == "win32" and not LEGACY_DATA.exists():
    DEFAULT_DATA = Path(os.getenv("LOCALAPPDATA", Path.home()/"AppData/Local"))/"Jiumi"/"client"
DATA = Path(os.getenv("PET_HOME", DEFAULT_DATA))
DATA.mkdir(mode=0o700,parents=True,exist_ok=True)
URL = os.getenv("PET_API","http://127.0.0.1:8769").rstrip("/")
SESSION = DATA/("session-"+hashlib.sha256(URL.encode()).hexdigest()[:16])


def write(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
        f.write(data.encode())
    os.replace(f.name,path)


def api(path,method="GET",body=None):
    headers={"Content-Type":"application/json"}
    if SESSION.exists():
        headers["Authorization"]="Bearer "+SESSION.read_text(encoding="utf-8")
    req=Request(URL+"/api/"+path, data=json.dumps(body).encode() if body is not None else None, headers=headers,method=method)
    try:
        with urlopen(req,timeout=10) as response:
            return json.load(response)
    except HTTPError as error:
        if error.code==401:
            raise PermissionError("需要重新授权") from error
        raise ValueError(f"HTTP {error.code}: "+json.load(error)["error"]) from error


def connect():
    pair=api("pair/start","POST",{})
    page=URL+"/studio#pair="+pair["code"]
    print("请在浏览器中登录并确认授权："+page,file=sys.stderr,flush=True)
    webbrowser.open(page)
    for _ in range(145):
        result=api("pair/claim","POST",{"secret":pair["secret"]})
        if "token" in result:
            write(SESSION,result["token"])
            return "已连接"
        time.sleep(2)
    raise ValueError("授权已过期，请重新连接")


def folder(pid):
    path=DATA/"pets"/str(uuid.UUID(pid))
    path.mkdir(exist_ok=True,parents=True)
    return path


def store(pet):
    write(folder(pet["id"])/"pet.json",json.dumps(pet,ensure_ascii=False))
    return {"id":pet["id"],"name":pet["name"],"revision":pet["revision"]}


def read(pid):
    pet=json.loads((folder(pid)/"pet.json").read_text(encoding="utf-8"))
    progress=DATA/"progress"/str(uuid.UUID(pid))/str(pet["revision"])
    for module in pet.get("modules",[]):
        path=progress/module["id"]
        if path.is_file():
            value=int(path.read_text(encoding="utf-8"))
            if abs(value)<2**53:
                pet.setdefault("moduleState",{})[module["id"]]=value
    return pet


def create(name,color=None,image=None,animal=None,modules=None,character=None,layers=None,language="zh-CN"):
    rig=None
    if not image:
        rig={"kind":"humanoid","style":character,"poses":json.loads((ROOT/"runtime/knight-poses.json").read_text(encoding="utf-8"))} if character in ("knight","humanoid") else {"kind":"sugar","species":animal or "chick"}
    color=color or ("#4d8792" if character in ("knight","humanoid") else SUGAR_COLORS.get(animal or "chick","#fac763"))
    portrait=ROOT/"animals"/((animal or "chick")+".png")
    if rig and rig["kind"]=="sugar" and portrait.is_file():image=portrait
    if not 1 <= len(name.strip()) <= 40 or not re.fullmatch(r"#[0-9a-fA-F]{6}",color):
        raise ValueError("请输入名字（1–40 字）和六位十六进制毛色")
    art=""
    if image:
        raw=Path(image).read_bytes()
        if not raw.startswith(b"\x89PNG\r\n\x1a\n") or len(raw)>3000000:
            raise ValueError("请提供 3 MB 以内的 PNG")
        art="data:image/png;base64,"+base64.b64encode(raw).decode()
    role=dict(id=str(uuid.uuid4()),name=name.strip(),color=color,image=art,defaultLanguage=language,plugins=[],revision=0)
    if layers:
        if not rig:raise ValueError("分件素材需要角色模板")
        rig["layers"]=layers
    if rig:role["rig"]=rig
    modules=list(modules or [])
    if len(modules)<8 and not any(m.get("id")=="chatter" for m in modules):
        modules.append(json.loads((ROOT/"runtime/chatter.json").read_text(encoding="utf-8")))
    if modules:
        role["modules"]=modules
        role["plugins"]=[m["id"] for m in modules]
    validate_portable(role)
    result=store(role)
    result["preview"]=str(designer(result["id"]))
    return result


def install_module(pid, module, module_id, version, clips=None):
    """Install one pinned module and its missing character clips as a single edit."""
    validate_module(module)
    if module["id"] != module_id or module["version"] != version:
        raise ValueError("下载的插件与所选 ID 或版本不符")
    if clips is not None and not isinstance(clips, dict):
        raise ValueError("动作配置应为动作名到动作帧的映射")
    directory = folder(pid)
    with (directory / ".install.lock").open("a+b") as lock:
        if os.name == "nt":
            import msvcrt
            lock.seek(0)
            msvcrt.locking(lock.fileno(), msvcrt.LK_LOCK, 1)
        else:
            import fcntl
            fcntl.flock(lock, fcntl.LOCK_EX)
        role = read(pid)
        modules = role.setdefault("modules", [])
        previous = next((m for m in modules if m["id"] == module_id), None)
        if previous:
            if previous["version"] > version or (previous["version"] == version and previous != module):
                raise ValueError("已安装更高版本或同版本内容冲突")
            modules[modules.index(previous)] = module
        else:
            modules.append(module)
        for key, clip in (clips or {}).items():
            installed = role.setdefault("clips", {})
            if key in installed and installed[key] != clip:
                raise ValueError("角色已有同名动作：" + key)
            installed[key] = clip
        if module_id not in role["plugins"]:
            role["plugins"].append(module_id)
        validate_portable(role)
        store(role)
        return {"pet_id":role["id"], "module_id":module_id, "version":version,
                "preview":str(designer(pid))}


def restore(pid):
    pet=api("pets/"+str(uuid.UUID(pid)))
    catalog=api("plugins")
    write(folder(pid)/"catalog.json",json.dumps(catalog))
    return store(pet)


def save(pid):
    pet=read(pid)
    try:
        saved=api("pets/"+pid,"PUT",pet)
    except PermissionError:
        connect()
        saved=api("pets/"+pid,"PUT",pet)
    return store(saved)


def import_package(path, extensions=None):
    """Materialize a trusted studio get_pet result in the local library."""
    pet=json.loads(Path(path).read_text(encoding="utf-8"))
    validate_portable(pet)
    pid=str(uuid.UUID(pet["id"]))
    if pet["id"]!=pid or not isinstance(pet["revision"],int) or pet["revision"]<0:
        raise ValueError("角色包 ID 或版本无效")
    if not isinstance(pet["name"],str) or not re.fullmatch(r"#[0-9a-fA-F]{6}",pet["color"]):
        raise ValueError("角色包外观无效")
    image=pet.get("image","")
    if image and (not image.startswith("data:image/png;base64,") or len(image)>4_000_022):
        raise ValueError("角色图无效")
    existing=folder(pid)/"pet.json"
    previous=read(pid) if existing.exists() else pet
    only_progress=all(previous.get(k)==pet.get(k) for k in previous.keys()|pet.keys() if k!="moduleState")
    if not only_progress and not (pet["revision"]==0 and previous["revision"]==0):
        raise ValueError("本机已有不同版本，请先保留本机修改")
    if extensions:
        catalog=json.loads(Path(extensions).read_text(encoding="utf-8"))
        if not isinstance(catalog,list) or not all(isinstance(rule,dict) for rule in catalog):
            raise ValueError("扩展目录格式无效")
        write(folder(pid)/"catalog.json",json.dumps(catalog))
    result=store(pet)
    # An explicitly imported snapshot supersedes prior progress for this revision.
    progress=DATA/"progress"/pid/str(pet["revision"])
    for module in pet.get("modules",[]):
        (progress/module["id"]).unlink(missing_ok=True)
    return result


def initial_signature(pet):
    return hashlib.sha256(json.dumps(pet,sort_keys=True).encode()).hexdigest()


def designer(pid):
    base=folder(pid)
    rules=json.loads((base/"catalog.json").read_text(encoding="utf-8")) if (base/"catalog.json").exists() else []
    draft_path=base/"appearance-draft.json"
    draft=json.loads(draft_path.read_text(encoding="utf-8")) if draft_path.exists() else {}
    saved=draft.get("values",{}) if draft.get("base")==initial_signature(read(pid)) else {}
    html=render_preview(read(pid),rules,saved)
    page=base/"designer.html"
    write(page,html)
    return page


def preview(pid):
    page=designer(pid)
    webbrowser.open(page.as_uri())
    return str(page)


def window_page(pid):
    pet=read(pid)
    base=folder(pid)
    rules=json.loads((base/"catalog.json").read_text(encoding="utf-8")) if (base/"catalog.json").exists() else []
    payload=json.dumps([pet,rules]).replace("<","\\u003c")
    html="""<!doctype html><meta charset=utf-8><style>*{box-sizing:border-box}body{margin:0;background:transparent;text-align:center;font:13px system-ui}button{width:145px;height:140px;background:transparent;border:0;position:relative;cursor:pointer}footer{display:inline-block;background:#fff8e8;color:#47392c;border-radius:10px;padding:2px 10px;user-select:none}footer[hidden]{display:none}body{position:absolute;bottom:0;width:100%;height:170px}body>aside{position:absolute!important;bottom:100%;width:100%!important}</style><button id="stage" title="轻点抚摸，长按拖动"></button><br><footer id="label" hidden></footer><script>"""
    html=html.replace("<!doctype html>","<!doctype html><html lang=\""+("en" if pet.get("defaultLanguage")=="en" else "zh-CN")+"\">")
    if pet.get("defaultLanguage") == "en":
        html=html.replace("轻点抚摸，长按拖动", "Tap to pet, hold to move")
    html+=player_source([pet["rig"]["kind"]] if pet.get("rig") else [])+"\nconst [pet,rules]="+payload+";"
    html+="for(const m of [...(pet.modules||[]),...rules]){const flag=window.petPluginOverrides?.[m.id];if(typeof flag==='boolean'){pet.plugins=pet.plugins.filter(id=>id!==m.id);if(flag)pet.plugins.push(m.id)}}"
    html+="const channel=window.webkit?.messageHandlers?.petSession;const host=channel?{nativeMenu:true,speechLayout:show=>channel.postMessage({method:'speechLayout',visible:show?'yes':'no'}),session:(method,target)=>channel.postMessage({method,...target}),layout:show=>channel.postMessage({method:'layout',visible:show?'yes':'no'})}:undefined;mountPet(stage,pet,rules,host);label.textContent=pet.name;stage.addEventListener('pet.tap',e=>label.textContent=pet.name+' · '+e.detail.count);</script>"
    page=base/"preview.html"
    write(page,html)
    return page


WINDOWS_HOST = ROOT/"runtime/windows"


def publish_windows(destination, artifacts):
    subprocess.run([
        "dotnet", "publish", str(WINDOWS_HOST/"Jiumi.csproj"), "-c", "Release",
        "--self-contained", "true", "--artifacts-path", str(artifacts),
        "-o", str(destination),
    ], check=True, stdout=sys.stderr)


def windows_host():
    source = b"".join(path.read_bytes() for path in sorted(WINDOWS_HOST.iterdir())
                      if path.suffix in (".cs", ".csproj", ".ico"))
    target = DATA/("windows-host-"+hashlib.sha256(source).hexdigest()[:12])
    if not (target/"Jiumi.exe").is_file():
        with tempfile.TemporaryDirectory(dir=DATA) as temporary:
            staged = Path(temporary)/"host"
            publish_windows(staged, Path(temporary)/"build")
            try:
                staged.rename(target)
            except OSError:
                if not (target/"Jiumi.exe").is_file():
                    raise
    return target/"Jiumi.exe"


def launch(pid,bridge=False):
    page=window_page(pid)
    if sys.platform=="win32":
        if bridge:
            raise ValueError("Windows 暂不支持会话桥接")
        subprocess.Popen([str(windows_host()),str(page),str(uuid.UUID(pid)),
                          read(pid).get("defaultLanguage","zh-CN"),"Jiumi"],
                         stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        return str(page)
    if sys.platform!="darwin":
        webbrowser.open(page.as_uri())
        return str(page)
    src=ROOT/"runtime/Sprite.swift"
    binary=DATA/("WindowPet-"+hashlib.sha256(src.read_bytes()).hexdigest()[:12])
    if not binary.exists():
        with tempfile.TemporaryDirectory(dir=DATA) as temp:
            out=Path(temp)/"WindowPet"
            subprocess.run(["swiftc",str(src),"-o",str(out)],check=True)
            os.replace(out,binary)
    process=subprocess.Popen([str(binary),str(page)],env={**os.environ,"JIUMI_DEFAULT_LANGUAGE":read(pid).get("defaultLanguage","zh-CN"),"JIUMI_CLIENT_ICON":str(ROOT/"runtime/Jiumi.icns")},start_new_session=True,stdin=subprocess.PIPE if bridge else subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return process if bridge else str(page)


def desktop_app(pid, directory, client_name="Jiumi"):
    """Build a native launcher with an embedded offline pet."""
    if sys.platform == "win32":
        return windows_app(pid, directory, client_name)
    if sys.platform != "darwin":
        raise ValueError("请在 macOS 上构建桌面发行包")
    destination = Path(directory).resolve()
    destination.mkdir(parents=True,exist_ok=True)
    pid = str(uuid.UUID(pid))
    if not client_name.strip() or client_name in (".","..") or any(c in client_name for c in "/:\x00") or len(client_name.encode()) > 240:
        raise ValueError("客户端名称无效")
    bundle = destination / (client_name+".app")
    if bundle.exists():
        info_path = bundle/"Contents/Info.plist"
        if info_path.is_file() and plistlib.loads(info_path.read_bytes()).get("CFBundleIdentifier") != "studio.jiumi.pet."+pid:
            destination = destination/pid
            destination.mkdir(exist_ok=True)
            bundle = destination/bundle.name
    if bundle.exists():
        raise ValueError("目标应用已存在，请选择新的输出目录")
    with tempfile.TemporaryDirectory(dir=destination) as temporary:
        staged = Path(temporary) / bundle.name
        contents = staged / "Contents"
        binary = contents / "MacOS/Jiumi"
        binary.parent.mkdir(parents=True)
        resources = contents / "Resources"
        resources.mkdir()
        shutil.copy2(window_page(pid),resources/"pet.html")
        shutil.copy2(ROOT/"runtime/Jiumi.icns",resources/"Jiumi.icns")
        info = dict(CFBundleExecutable="Jiumi", CFBundleIdentifier="studio.jiumi.pet."+pid,
                    CFBundleName=client_name, CFBundleDisplayName=client_name, CFBundleShortVersionString="1.0", CFBundlePackageType="APPL",
                    JiumiDefaultLanguage=read(pid).get("defaultLanguage","zh-CN"), CFBundleVersion="1", CFBundleIconFile="Jiumi.icns", LSUIElement=True)
        (contents/"Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["swiftc",str(ROOT/"runtime/Sprite.swift"),"-o",str(binary)],check=True)
        subprocess.run(["codesign","--force","--sign","-",str(staged)],check=True)
        staged.rename(bundle)
    return str(bundle)


def windows_app(pid, directory, client_name):
    pid = str(uuid.UUID(pid))
    if (not client_name.strip() or client_name.endswith((".", " ")) or
            len(client_name) > 120 or any(ord(c) < 32 or c in '<>:"/\\|?*' for c in client_name) or
            re.fullmatch(r"(?i:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\..*)?", client_name)):
        raise ValueError("客户端名称无效")
    destination = Path(directory).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    bundle = destination/(client_name+"-Windows")
    existing_id = bundle/"pet-id.txt"
    if existing_id.is_file() and existing_id.read_text(encoding="utf-8").strip() != pid:
        bundle = destination/pid/bundle.name
        bundle.parent.mkdir(exist_ok=True)
    if bundle.exists():
        raise ValueError("目标应用已存在，请选择新的输出目录")
    with tempfile.TemporaryDirectory(dir=bundle.parent) as temporary:
        staged = Path(temporary)/"host"
        publish_windows(staged, Path(temporary)/"build")
        shutil.copy2(window_page(pid), staged/"pet.html")
        write(staged/"pet-id.txt", pid)
        write(staged/"language.txt", read(pid).get("defaultLanguage", "zh-CN"))
        write(staged/"client-name.txt", client_name)
        staged.rename(bundle)
    return str(bundle/"Jiumi.exe")


def main():
    parser=argparse.ArgumentParser()
    sub=parser.add_subparsers(dest="cmd",required=True)
    c=sub.add_parser("create"); c.add_argument("name"); c.add_argument("--color"); c.add_argument("--image"); c.add_argument("--animal",choices=["chick","bunny","pig","cat","cow","elephant"],default=None)
    c.add_argument("--character",choices=["knight","humanoid"])
    c.add_argument("--layers",type=Path,help="可选的关节名与内嵌 PNG 对照 JSON")
    c.add_argument("--module",action="append",type=Path,default=[],help="随角色启用一个本地插件 JSON，可重复")
    c.add_argument("--language",choices=["en","zh-CN"],default="zh-CN",help="制作请求使用的语言，作为客户端初始语言")
    c.add_argument("--client-name",default="Jiumi",help="仅在明确指定客户端名称时覆盖默认值")
    c.add_argument("--html-only",action="store_true",help="只交付 HTML 预览")
    c.add_argument("--output",type=Path,help="交付目录，默认为本机角色目录")
    for cmd in ("open","save","restore","preview"):
        sub.add_parser(cmd).add_argument("id")
    for cmd in ("connect","list","local"):
        sub.add_parser(cmd)
    app_builder=sub.add_parser("desktop-app")
    app_builder.add_argument("id"); app_builder.add_argument("directory")
    app_builder.add_argument("--client-name",default="Jiumi")
    install=sub.add_parser("install-module")
    install.add_argument("id"); install.add_argument("module",type=Path)
    install.add_argument("--module-id",required=True); install.add_argument("--version",type=int,required=True)
    install.add_argument("--clips",type=Path,help="可选的角色动作 JSON 映射")
    importer=sub.add_parser("import")
    importer.add_argument("path")
    importer.add_argument("--extensions")
    a=parser.parse_args()
    if a.cmd=="create":
        result=create(a.name,a.color,a.image,a.animal,[json.loads(path.read_text(encoding="utf-8")) for path in a.module],a.character,json.loads(a.layers.read_text(encoding="utf-8")) if a.layers else None,a.language)
        destination=a.output.resolve() if a.output else folder(result["id"])
        if a.output:
            destination.mkdir(parents=True,exist_ok=True)
            html=destination/("Jiumi-"+result["id"]+".html")
            shutil.copy2(result["preview"],html)
            result["preview"]=str(html)
        if sys.platform in ("darwin","win32") and not a.html_only:
            try:
                result["desktop_app"]=desktop_app(result["id"],destination,a.client_name)
            except (subprocess.CalledProcessError,OSError,ValueError) as error:
                result["desktop_error"]=str(error)
                print(json.dumps(result,ensure_ascii=False))
                sys.exit(1)
    elif a.cmd=="desktop-app": result=desktop_app(a.id,a.directory,a.client_name)
    elif a.cmd=="install-module":
        result=install_module(a.id,json.loads(a.module.read_text(encoding="utf-8")),a.module_id,a.version,
                              json.loads(a.clips.read_text(encoding="utf-8")) if a.clips else None)
    elif a.cmd=="import": result=import_package(a.path,a.extensions)
    elif a.cmd=="connect": result=connect()
    elif a.cmd=="list": result=[{"id":p["id"],"name":p["name"],"revision":p["revision"]} for p in api("pets")]
    elif a.cmd=="local": result=[{"id":p.parent.name,"name":json.loads(p.read_text(encoding="utf-8"))["name"]} for p in (DATA/"pets").glob("*/pet.json")]
    else: result={"preview":preview,"open":launch,"save":save,"restore":restore}[a.cmd](a.id)
    print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__":
    try:
        main()
    except (ValueError,OSError,subprocess.CalledProcessError) as e:
        sys.exit(str(e))
