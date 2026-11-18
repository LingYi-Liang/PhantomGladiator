"""Convert decoded weapon combat execution timelines into exact weapon lookups."""
import argparse
import json
from pathlib import Path


def lua(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (tuple, list)):
        return "{" + ",".join(map(lua, value)) + "}"
    if isinstance(value, float):
        return f"{value:.5f}".rstrip("0").rstrip(".")
    return str(value)


def convert(source):
    out = ["-- Weapon combat execution data generated from native ExecutionAnims and ExecutionTimeline.",
           "local pairsByIndex={}", "local byConfig={}"]
    configs = {}
    unique = {}
    default_only = {err["ability"] for err in source["errors"]}
    for pair in source["pairs"]:
        if pair["field"] != "ExecutionAnims" or pair["type"] != "Execution.Type.Combat":
            continue
        key = tuple(lua(pair[k]) for k in ("execution", "executed", "executor_required", "executor_ignored",
                                          "target_required", "target_ignored"))
        refs = configs.setdefault(pair["source"].lower(), [])
        if key in unique:
            refs.append(unique[key])
            continue
        att = source["executors"][pair["execution"]]
        defn = source["executed"][pair["executed"]]
        hits = [v for v in att["montages"] if v["skeleton"] == "Hun_Skin_Skeleton"]
        victims = [v for v in defn["montages"] if v["timeline"] == "ExecutionTimeline"]
        assert len(hits) == 1 and victims and pair["continuous"] == "None", pair
        assert len({(m["skeleton"], round(m["start"] + m["length"] / m["rate"], 4)) for m in victims}) == 1, pair
        hit, victim = hits[0], victims[0]
        assert len(hit["segments"]) == 1
        segment = hit["segments"][0]
        rate = segment["rate"] * hit["rate"]
        duration = hit["start"] + (segment["to"] - segment["from"]) / rate
        victim_end = victim["start"] + victim["length"] / victim["rate"]
        i = len(unique) + 1
        unique[key] = i
        refs.append(i)
        out.append(f"pairsByIndex[{i}]={{")
        for k in ("execution", "executed", "executor_required", "executor_ignored", "target_required", "target_ignored"):
            out.append("    " + k + "=" + lua(pair[k]) + ",")
        out.append(f"    victim={lua(victim['montage'])},victim_skeleton={lua(victim['skeleton'])},"
                   f"default_only={lua(pair['executed'] in default_only)},")
        out.append(f"    timing={{montage={lua(hit['montage'])},clip={lua(segment['clip'])},"
                   f"clip_from={lua(segment['from'])},clip_to={lua(segment['to'])},rate={lua(rate)},"
                   f"start={lua(hit['start'])},segments=1,executor={lua(duration)},")
        out.append(f"        executed={{[{lua(pair['executed'].rsplit('.', 1)[-1])}]={lua(victim_end)}}},")
        camera = next((cam for cam in att["cameras"] if not cam["requires"]), None)
        if camera and camera["frames"]:
            out.append(f"        camera={{start={lua(camera['start'])},duration={lua(camera['duration'])},"
                       f"stop_yaw={lua(camera['stop_yaw'])},provider={lua(camera['provider_class'] or '')},frames={{")
            for frame in camera["frames"]:
                out.append("            " + lua([frame["t"], *frame["look"], *frame["rot"],
                                                 frame["dist"], *frame["socket"]]) + ",")
            out.append("        }},")
        out.append("    }}")
    for path, refs in configs.items():
        out.append(f"byConfig[{lua(path)}]={{" + ",".join(f"pairsByIndex[{i}]" for i in refs) + "}")
    out.extend(["local empty={}", "return {forConfig=function(path)",
                "    return type(path)=='string' and byConfig[path:lower()] or empty", "end}", ""])
    return "\n".join(out)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("decoded", type=Path, help="weapon-pairs.json with default execution timelines resolved")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(convert(json.loads(args.decoded.read_text(encoding="utf8"))), encoding="utf-8", newline="\n")
