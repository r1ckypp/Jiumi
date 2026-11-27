"""Validate optional portable pet data before writing or embedding it."""
import base64
import hashlib
import json
import re

SUGAR_COLORS={"chick":"#fac763","pig":"#99d3ec","cat":"#edb278","cow":"#f4ecdc","bunny":"#ecd6d5","elephant":"#adbbd8"}

PORTABLE_FIELDS = ("defaultLanguage", "rig", "clips", "motionPools", "modules", "moduleState")


def check(ok, message):
    if not ok:
        raise ValueError(message)


def valid_id(value):
    return isinstance(value,str) and bool(re.fullmatch(r"[a-z][a-z0-9-]{0,47}",value)) and value != "constructor"


def validate_machine(m):
    states=m.get("states")
    check(type(m.get("priority")) is int and 0<=m["priority"]<=100,"状态优先级无效")
    check(isinstance(states,dict) and 1<=len(states)<=32 and
          all(valid_id(k) and k!="free" and isinstance(v,dict) for k,v in states.items()),"状态定义无效")
    names=set(states)
    exits=names|{"$base","$resume"}

    def routes(table,targets):
        check(isinstance(table,dict) and len(table)<=32 and
              all(isinstance(e,str) and 0<len(e)<=160 and isinstance(t,str) and t in targets
                  for e,t in table.items()),"事件或转移目标无效")

    routes(m.get("enter"),names)
    check(bool(m["enter"]),"需要入口事件")
    menu=m.get("menu",{})
    check(isinstance(menu,dict) and len(menu)<=8 and all(
        valid_id(key) and isinstance(label,str) and label.strip() and len(label)<=80
        and f"menu.{m['id']}.{key}" in m["enter"] for key,label in menu.items()
    ),"插件菜单或入口事件无效")
    for state in states.values():
        check(valid_id(state.get("motion")),"动作名无效")
        routes(state.get("on",{}),exits)
        if "timeoutMs" in state:
            duration=state["timeoutMs"]
            check(type(duration) is int and 1<=duration<=2147483647,"状态超时时间无效")
        resume=state.get("resumeAt","$self")
        check(isinstance(resume,str) and resume in names|{"$self","$discard"},"恢复目标无效")
        if "after" in state:
            after=state["after"]
            check(isinstance(after,str) and after in exits,"动作完成目标无效")

    for start in states:
        visited=set()
        key=start
        while key in states:
            check(key not in visited,"动作完成转移不能形成循环")
            visited.add(key)
            key=states[key].get("after")


def validate_module(module):
    check(isinstance(module,dict) and valid_id(module.get("id")), "插件 ID 无效")
    check(module.get("api")==1 and type(module.get("version")) is int and 0<module["version"]<2**53, "插件版本无效")
    check(isinstance(module.get("name"),str) and 0<len(module["name"])<=80, "插件名称无效")
    if module.get("kind")=="speech":
        lines=module.get("lines")
        check(isinstance(lines,list) and 1<=len(lines)<=100 and all(isinstance(s,str) and s.strip() and len(s)<=48 for s in lines),"气泡台词无效")
        low,high,duration=(module.get(k) for k in ("minSeconds","maxSeconds","durationSeconds"))
        check(all(type(n) is int for n in (low,high,duration)) and 1<=low<=high<=3600 and 1<=duration<=30,"气泡间隔无效")
        return
    if module.get("kind")=="session-notice":
        def label(s,limit):
            return isinstance(s,str) and bool(s.strip()) and len(s)<=limit
        clear=module.get("clear")
        check(label(module.get("show"),160) and label(module.get("title"),80) and
              module.get("action")=="session.open" and isinstance(clear,list) and 1<=len(clear)<=16
              and all(label(e,160) and e!=module["show"] for e in clear),"会话提示规则无效")
        return
    if module.get("kind")=="state-machine":
        validate_machine(module)
        return
    events=module.get("events")
    check(isinstance(events,list) and len(events)<=24 and all(isinstance(e,str) and 0<len(e)<=160 for e in events), "事件订阅无效")
    caps=module.get("capabilities")
    check(isinstance(caps,list) and len(caps)<=2 and all(c in ("state","motion") for c in caps), "插件能力不受支持")
    check(isinstance(module.get("wasm"),str) and len(module["wasm"])<=90000, "插件模块过大")
    binary=base64.b64decode(module["wasm"],validate=True)
    check(binary.startswith(b"\x00asm\x01\x00\x00\x00") and hashlib.sha256(binary).hexdigest()==module.get("sha256"), "插件校验失败")


def validate_portable(pet):
    check(pet.get("defaultLanguage","zh-CN") in ("en","zh-CN"),"不支持的客户端语言")
    if "rig" in pet:
        rig=pet["rig"]
        check(isinstance(rig,dict) and rig.get("kind") in ("sugar","humanoid"),"角色模板无效")
        if rig["kind"]=="sugar":
            check(rig.get("species") in ("chick","pig","bunny","cat","cow","elephant"),"方糖物种无效")
        check("style" not in rig or rig["style"] in ("knight","humanoid"),"人形外观无效")
        layers=rig.get("layers",{})
        check(isinstance(layers,dict) and len(layers)<=32 and len(json.dumps(layers))<=4_000_000,"分件素材过大")
        for key,texture in layers.items():
            check(isinstance(key,str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9]{0,31}",key) and isinstance(texture,str) and texture.startswith("data:image/png;base64,"),"分件素材无效")
            check(base64.b64decode(texture[22:],validate=True).startswith(b"\x89PNG\r\n\x1a\n"),"分件需要 PNG")
        poses=rig.get("poses",{})
        check(isinstance(poses,dict) and len(poses)<=128,"姿势库无效")
        for key,pose in poses.items():
            check(valid_id(key) and isinstance(pose,dict) and type(pose.get("duration")) is int and 40<=pose["duration"]<=30000,"姿势时序无效")
            tracks=pose.get("joints")
            check(isinstance(tracks,dict) and 1<=len(tracks)<=32 and all(isinstance(t,list) and 2<=len(t)<=64 and all(type(a) in (int,float) and -720<=a<=720 for a in t) for t in tracks.values()),"关节轨道无效")
            check("label" not in pose or isinstance(pose["label"],str) and len(pose["label"])<=64,"姿势名称无效")
    pools=pet.get("motionPools",{})
    check(isinstance(pools,dict) and len(pools)<=256,"动作池数量无效")
    for key,entries in pools.items():
        check(valid_id(key) and isinstance(entries,list) and 1<=len(entries)<=256 and
              all(valid_id(e) for e in entries) and len(set(entries))==len(entries),"动作池无效")
    clips=pet.get("clips",{})
    check(isinstance(clips,dict) and len(clips)<=256 and all(valid_id(k) for k in clips) and len(json.dumps(clips,separators=(",",":")))<=8_000_000,"动作包无效")
    for clip in clips.values():
        check(isinstance(clip,dict) and type(clip.get("loop")) is bool and type(clip.get("frameMs")) is int and 40<=clip["frameMs"]<=1000,"动作时序无效")
        if "label" in clip:
            check(isinstance(clip["label"],str) and 1<=len(clip["label"])<=64,"动作名称无效")
        frames=clip.get("frames")
        check(isinstance(frames,list) and 1<=len(frames)<=32,"动作帧数量无效")
        total=0
        for frame in frames:
            check(isinstance(frame,str) and frame.startswith("data:image/png;base64,"),"动作帧应为内嵌 PNG")
            data=base64.b64decode(frame[22:],validate=True)
            total+=len(data)
            check(data.startswith(b"\x89PNG\r\n\x1a\n") and total<=3_000_000,"动作帧无效或过大")
    modules=pet.get("modules",[])
    check(isinstance(modules,list) and len(modules)<=8,"插件包数量无效")
    ids=set()
    for module in modules:
        validate_module(module)
        check(module["id"] not in ids,"插件 ID 重复")
        ids.add(module["id"])
    state=pet.get("moduleState",{})
    check(isinstance(state,dict) and len(state)<=32 and all(valid_id(k) and type(v) is int and abs(v)<2**53 for k,v in state.items()),"插件状态无效")
