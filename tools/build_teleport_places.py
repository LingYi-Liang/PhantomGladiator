"""Build panel/teleport-places.json from two local, offline sources (never shipped themselves):

  * the game's own developer teleport table, decoded to JSON (DA_GlobalTeleportPointData)
  * the boss placement table made for the boss maps (boss_master.json: unit, name, world, position in metres)

Usage: python -I -X utf8 tools/build_teleport_places.py <DA_GlobalTeleportPointData.json> <boss_master.json>
The outputs hold only names, world ids and coordinates: the JSON for the app, Scripts/teleport_places.lua for the
mod. English names ("en") go into the JSON only: a boss's from the app's own unit list (panel/prototype/units.js), a
world's and a developer point's from the tables below. The app sends a place's code and the mod looks the coordinates up in its own table, so no coordinate ever comes
from outside the mod. A code is a hash of the place id: it stays the same when the list is rebuilt, so an app and a
mod of different builds never mean different places by one code.
"""
import hashlib
import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "panel" / "teleport-places.json"
LUA = ROOT / "Mods" / "PhantomGladiator" / "Scripts" / "teleport_places.lua"
# Worlds in story order, with the name shown as the group title. A world the table does not know keeps its id.
WORLDS = [
    ("PBZ_WP_ZhuLinGuWu", "序章 · 竹林古屋"),
    ("PBZ_Xigu_WP", "悲泣溪谷"),
    ("PBZ_Fujizhilin_WP", "血色森林"),
    ("PBZ_Zhengdaodaying_WP", "陆家村 · 正道大营"),
    ("PBZ_Pangzhen_WP", "庞镇 · 梅谷湖"),
    ("PBZ_Houjie_WP", "后街"),
    ("PBZ_Ximeng_WP", "戏梦山庄"),
    ("PBZ_DengDingShanDao_WP", "枷笼山"),
    ("PBZ_Duanhun_WP", "断魂山"),
]
# English group titles: the map names of the app's unit list where it has one.
WORLDS_EN = {
    "PBZ_WP_ZhuLinGuWu": "Prologue",
    "PBZ_Xigu_WP": "Weeping Creek Valley",
    "PBZ_Fujizhilin_WP": "Crimson Forest",
    "PBZ_Zhengdaodaying_WP": "Village of Lu · Mandate Encampment",
    "PBZ_Pangzhen_WP": "Pangzhen · Meigu Lake",
    "PBZ_Houjie_WP": "Back Street",
    "PBZ_Ximeng_WP": "Mirage Estate",
    "PBZ_DengDingShanDao_WP": "Mountain of Imprisonment",
    "PBZ_Duanhun_WP": "Mount Soulrend",
}
# English names of the developer points, by the name shown in Chinese. Character names follow the unit list.
DEV_EN = {
    "教学关": "Tutorial",
    "斧老大": "Peng Meng, the Axemaster",
    "新娘门前": "Outside the bride's door",
    "玉儿SEQ": "Yu'er cutscene",
    "庇护所": "Shelter",
    "大乱斗": "Brawl",
    "飞贼密道入口门前": "Outside the thieves' secret passage",
    "圣母娘娘庙": "Temple of the Merciful Lady",
    "酒窖起始点": "Wine cellar start",
    "医者站": "Healer's post",
    "俯瞰庞镇": "Overlooking Pangzhen",
    "南门出标题": "South gate (title card)",
    "seq051seq052boss火流星": "Seq 051–052 boss: Blaze",
    "seq069雷当": "Seq 069: Lei Dang",
    "主街": "Main street",
    "seq054": "Seq 054",
    "seq055幻鬼": "Seq 055: phantom",
    "终点去往后街": "Exit to Back Street",
    "骨婉约": "Gu Wanyue, the Wailing Wraith",
    "医者": "Healer",
}
# Units the unit list does not carry, named as their listed sibling is.
UNIT_EN = {
    "BP_Monster_MoTian_LongZhu_02": "The Gold-Masked One",
    "BP_Monster_MoTian_LongZhu_03": "The Gold-Masked One",
    "BP_Monster_MoTian_LongZhu_04": "The Gold-Masked One",
}
SKIP_WORLDS = {"Rhm_Test_wp"}          # a developer test level
RENAME = {"fulaoda": "斧老大", "教学": "教学关"}
BOSS_LIFT_CM = 120.0                   # above the spawner, so the player lands on the floor instead of in it
SAME_PLACE_M = 30.0                    # two placements of one boss closer than this are one place
MAX_COORD_CM = 2e7                     # as teleport.lua's Teleport.MAX_COORD
DROPPED = []


def unit_names():
    source = (ROOT / "panel" / "prototype" / "units.js").read_text(encoding="utf-8")
    units = json.loads(source.split("window.PG_UNITS =", 1)[1].strip().removesuffix(";"))
    return {**{u["id"]: u["enName"] for u in units if u.get("enName")}, **UNIT_EN}


def yaw_of(q):
    x, y, z, w = q
    return round(math.degrees(math.atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))), 1)


def debug_places(path):
    data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    table = next(iter(data.values()))[0]["values"]["TeleportPointDatas"]
    out = {}
    for world, entry in table:
        if world in SKIP_WORLDS:
            continue
        for anchor in entry["AnchorData"]:
            desc = anchor["TeleportTargetDesc"]
            name = desc.split("-", 2)[-1]
            name = RENAME.get(name, name)
            t = anchor["TeleportTransform"]
            x, y, z = t["Translation"]
            out.setdefault(world, []).append({
                "id": f"dev:{world}:{desc}", "kind": "dev", "name": name, "order": desc,
                "x": round(x, 1), "y": round(y, 1), "z": round(z, 1), "yaw": yaw_of(t["Rotation"]),
            })
    for places in out.values():
        places.sort(key=lambda p: p.pop("order"))
    return out


def boss_places(path):
    bosses = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    out = {}
    for boss in bosses:
        kept = []
        for placement in boss["placements"]:
            world, loc = placement["world"], placement["loc"]
            # Spawners parked far above the map (about 1,000 km up) are not places anyone can stand.
            if max(abs(v) for v in loc) * 100.0 >= MAX_COORD_CM:
                DROPPED.append(f"{boss['zh_name']}@{world}")
                continue
            if any(w == world and math.dist(loc, other) < SAME_PLACE_M for w, other in kept):
                continue
            kept.append((world, loc))
            n = sum(1 for w, _ in kept if w == world)
            out.setdefault(world, []).append({
                "id": f"boss:{boss['unit']}:{world}:{n}", "kind": "boss", "name": boss["zh_name"], "unit": boss["unit"],
                "level": placement.get("level"),
                "x": round(loc[0] * 100.0, 1), "y": round(loc[1] * 100.0, 1), "z": round(loc[2] * 100.0 + BOSS_LIFT_CM, 1), "yaw": 0.0,
            })
    for places in out.values():
        places.sort(key=lambda p: (p["level"] or 0, p["name"], p["id"]))
    return out


def main():
    dev, boss = debug_places(sys.argv[1]), boss_places(sys.argv[2])
    known = dict(WORLDS)
    # Worlds without a confirmed name (a dream level and a sub-level, holding only wandering bosses) are left out.
    unnamed = sorted((set(dev) | set(boss)) - set(known))
    if unnamed:
        print("left out, no confirmed name:", ", ".join(unnamed))
    order = [w for w, _ in WORLDS]
    english = unit_names()
    groups = []
    for world in order:
        places = dev.get(world, []) + boss.get(world, [])
        for place in places:
            en = english.get(place["unit"]) if place["kind"] == "boss" else DEV_EN.get(place["name"])
            assert en, "no English name for " + place["id"]
            place["en"] = en
        if places:
            groups.append({"world": world, "name": known.get(world, world), "en": WORLDS_EN[world], "places": places})
    ids = [p["id"] for g in groups for p in g["places"]]
    assert len(ids) == len(set(ids)), "duplicate place id"
    lines = []
    for group in groups:
        for place in group["places"]:
            place["code"] = "T" + hashlib.sha1(place["id"].encode("utf-8")).hexdigest()[:10].upper()
            lines.append("%s={world=%s,x=%r,y=%r,z=%r,yaw=%r,name=%s}," % (
                place["code"], json.dumps(group["world"]), place["x"], place["y"], place["z"], place["yaw"],
                json.dumps(place["name"], ensure_ascii=False)))
    codes = [p["code"] for g in groups for p in g["places"]]
    assert len(codes) == len(set(codes)), "place code collision"
    LUA.write_text("-- Places the app can send the player to: code -> level name, position (cm), yaw (degrees), name.\n"
                   "-- Generated by tools/build_teleport_places.py; do not edit by hand.\n"
                   "return {\n" + "\n".join(lines) + "\n}\n", encoding="utf-8", newline="\n")
    OUT.write_text(json.dumps({"version": 1, "groups": groups}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"{OUT.name}: {len(groups)} worlds, {len(ids)} places "
          f"({sum(1 for g in groups for p in g['places'] if p['kind'] == 'dev')} dev, "
          f"{sum(1 for g in groups for p in g['places'] if p['kind'] == 'boss')} boss); "
          f"dropped {len(DROPPED)} parked spawners: {', '.join(sorted(set(DROPPED)))}")


if __name__ == "__main__":
    main()
