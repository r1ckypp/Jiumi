"""Assemble the offline editor for the Skill, CLI and website."""
import json
from pathlib import Path
import re

RUNTIME = Path(__file__).resolve().parent / "runtime"


def player_source(kinds=("sugar","humanoid")):
    files=["language.js","machines.js","notices.js","speech.js","plugin-host.js"]
    if kinds:
        files.append("rig-player.js")
        files.extend(kind+".js" for kind in ("sugar","humanoid") if kind in kinds)
    files.append("player.js")
    default = "const defaultPickup=" + (RUNTIME/"pickup.json").read_text() + ";"
    default += "\nconst defaultSpeech=" + (RUNTIME/"chatter.json").read_text() + ";"
    return "\n".join([default, *((RUNTIME / file).read_text() for file in files)])


def render_preview(pet=None, rules=(), draft=None, presets=None):
    def script_data(value):
        return json.dumps(value, ensure_ascii=True).replace("<", r"\u003c")

    parts = {
        "PLAYER": player_source([pet["rig"]["kind"]] if pet and pet.get("rig") else ([] if pet else ["sugar"])),
        "MAKER": (RUNTIME / "maker.js").read_text(),
        "PACKAGE": script_data([pet, rules]),
        "DRAFT": script_data(draft or {}),
        "PRESETS": script_data(presets or {}),
    }
    return re.sub(r"/\*(PLAYER|MAKER|PACKAGE|DRAFT|PRESETS)\*/",
                  lambda match: parts[match[1]], (RUNTIME / "designer.html").read_text())
