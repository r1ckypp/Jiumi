"""Optional local Claude Code hook adapter and macOS pet bridge."""
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import uuid

from urllib.parse import urlsplit
from pet import DATA, launch, write

EVENTS = {"UserPromptSubmit":"agent.started", "PreToolUse":"agent.resumed",
          "PermissionRequest":"agent.input_requested", "Stop":"agent.completed",
          "SessionEnd":"agent.closed"}


def normalize(payload):
    kind = EVENTS.get(payload.get("hook_event_name"))
    session = payload.get("session_id")
    if kind and isinstance(session,str) and 0<len(session)<=160:
        return dict(v=1,id=uuid.uuid4().hex,source="claude",session=session,type=kind,at=time.time_ns()//1000000)


def bind_session(pid, source, session, url):
    # Only this local command provides targets. Imported events and pet packs cannot.
    if not all(isinstance(x,str) and 0<len(x)<=160 and x.isprintable() for x in (source,session)):
        raise ValueError("无效的来源或会话标识")
    target=urlsplit(url)
    web=target.scheme=="https" and target.hostname and not target.username and not target.password
    thread=False
    if not web and target.netloc=="threads" and target.path=="/"+session and not (target.query or target.fragment):
        thread=(target.scheme.isalpha() and target.scheme not in {"file","http","data","javascript"}
                and session==str(uuid.UUID(session)))
    if not (web or thread) or len(url)>2048 or not url.isprintable():
        raise ValueError("请指定 HTTPS 会话地址或客户端的会话深链接")
    directory=DATA/"session-links"/str(uuid.UUID(pid))
    directory.mkdir(mode=0o700,parents=True,exist_ok=True)
    key=hashlib.sha256((source+"\0"+session).encode()).hexdigest()
    write(directory/key,url)


def address(pid):
    directory=Path("/tmp")/f"jiumi-events-{os.getuid()}"
    directory.mkdir(mode=0o700,exist_ok=True)
    stat=directory.lstat()
    if directory.is_symlink() or not directory.is_dir() or stat.st_uid!=os.getuid() or stat.st_mode & 0o077:
        raise ValueError("事件目录权限无效")
    return str(directory/hashlib.sha256(str(DATA/str(uuid.UUID(pid))).encode()).hexdigest()[:24])


def watch(pid):
    import fcntl
    path=address(pid)
    with open(path+".lock","a") as lock, socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as channel:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        Path(path).unlink(missing_ok=True)
        channel.bind(path)
        channel.settimeout(1)
        process=None
        try:
            process=launch(pid,bridge=True)
            while process.poll() is None:
                try:
                    data=channel.recv(4096)
                    if len(data)>=4096 or not isinstance(json.loads(data),dict):continue
                except (socket.timeout,ValueError,UnicodeError):
                    continue
                process.stdin.write(json.dumps(json.loads(data),ensure_ascii=False,separators=(",",":")).encode()+b"\n")
                process.stdin.flush()
        finally:
            Path(path).unlink(missing_ok=True)
            if process is not None and process.poll() is None:
                process.terminate()
                process.wait()


if __name__=="__main__":
    import argparse
    parser=argparse.ArgumentParser()
    parser.add_argument("mode",choices=["watch","claude","bind","emit"])
    parser.add_argument("pet_id",type=uuid.UUID)
    parser.add_argument("target",nargs="*")
    args=parser.parse_args()
    if args.mode=="bind":
        if len(args.target)!=3:parser.error("bind PET_ID SOURCE SESSION URL")
        bind_session(str(args.pet_id),*args.target)
    elif args.mode=="emit":
        event=json.load(sys.stdin)
        raw=json.dumps(event,ensure_ascii=False).encode()
        if len(raw)>=4096:parser.error("事件过大")
        with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as channel:
            channel.sendto(raw,address(str(args.pet_id)))
    elif args.mode=="watch":
        if sys.platform!="darwin":parser.error("本地监听窗口目前支持 macOS")
        watch(str(args.pet_id))
    else:
        try:
            event=normalize(json.load(sys.stdin))
            if event:
                with socket.socket(socket.AF_UNIX,socket.SOCK_DGRAM) as channel:
                    channel.setblocking(False)
                    channel.sendto(json.dumps(event).encode(),address(str(args.pet_id)))
        except (ValueError,OSError,AttributeError):
            pass  # Observational hooks must never block the coding session.
