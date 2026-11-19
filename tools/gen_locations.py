#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 windows/ios_loc.py 里的 DATA 地点表转换成 Swift 数据文件。

用法:
    python3 tools/gen_locations.py            # 生成到 ios-app/Xunidingwei/Generated/LocationData.swift
    python3 tools/gen_locations.py --check    # 只检查生成结果是否与仓库内文件一致

地点表格式(与 Windows 版完全一致):
    顶格行 = 国家/地区:  分组|中文名|英文别名(逗号分隔)
    缩进行 = 城市:        中文名|纬度|经度|英文别名(逗号分隔)
每个国家的第一个城市是"只输入国家名"时的默认城市。
"""
import argparse
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "windows" / "ios_loc.py"
TARGET = ROOT / "ios-app" / "Xunidingwei" / "Generated" / "LocationData.swift"


def read_data_block(path):
    text = path.read_text(encoding="utf-8")
    marker = 'DATA = """'
    start = text.index(marker) + len(marker)
    end = text.index('"""', start)
    return text[start:end]


def parse(data):
    countries = []
    for raw in data.splitlines():
        if not raw.strip():
            continue
        fields = [f.strip() for f in raw.strip().split("|")]
        if raw[0] not in (" ", "\t"):
            countries.append({
                "group": fields[0],
                "name": fields[1],
                "names": [fields[1]] + [a for a in (fields[2] if len(fields) > 2 else "").split(",") if a],
                "cities": [],
            })
        else:
            countries[-1]["cities"].append({
                "name": fields[0],
                "lat": float(fields[1]),
                "lon": float(fields[2]),
                "names": [fields[0]] + [a for a in (fields[3] if len(fields) > 3 else "").split(",") if a],
            })
    return countries


def swift_string_list(names):
    return "[" + ", ".join('"%s"' % n.replace('"', '\\"') for n in names) + "]"


def swift_float(value):
    text = repr(value)
    return text if ("." in text or "e" in text) else text + ".0"


def render(countries):
    lines = [
        "// 本文件由 tools/gen_locations.py 从 windows/ios_loc.py 自动生成，请勿手动修改。",
        "// 修改地点请改 windows/ios_loc.py 的 DATA 表，然后重新运行生成脚本。",
        "",
        "import Foundation",
        "",
        "enum LocationData {",
        "    static let places: [Place] = [",
    ]
    total = 0
    for country in countries:
        for city in country["cities"]:
            total += 1
            lines.append(
                '        Place(group: "%s", country: "%s", city: "%s", latitude: %s, longitude: %s,'
                % (country["group"], country["name"], city["name"],
                   swift_float(city["lat"]), swift_float(city["lon"]))
            )
            lines.append(
                "              countryNames: %s, cityNames: %s),"
                % (swift_string_list(country["names"]), swift_string_list(city["names"]))
            )
    lines.append("    ]")
    lines.append("}")
    lines.append("")
    return "\n".join(lines), total


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="只校验仓库内文件是否为最新")
    args = parser.parse_args(argv)

    countries = parse(read_data_block(SOURCE))
    content, total = render(countries)
    if not total:
        print("地点表是空的，检查 windows/ios_loc.py", file=sys.stderr)
        return 1

    if args.check:
        current = TARGET.read_text(encoding="utf-8") if TARGET.exists() else ""
        if current != content:
            print("LocationData.swift 与 ios_loc.py 不一致，请重新运行 tools/gen_locations.py", file=sys.stderr)
            return 1
        print("一致：%d 个城市" % total)
        return 0

    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(content, encoding="utf-8")
    print("已生成 %s（%d 个城市，%d 个国家/地区）" % (TARGET.relative_to(ROOT), total, len(countries)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
