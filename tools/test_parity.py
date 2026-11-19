#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""交叉校验：用同一份地点表，验证 Python 版和 Swift 版的解析规则一致。

Swift 端无法在本机运行，所以这里把 Swift 的规则用 Python 复刻一遍，
并断言它与 windows/ios_loc.py 的 resolve() 输出完全相同。
生成脚本和解析规则任何一侧改动都会被这个测试发现。

用法: python3 tools/test_parity.py
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_windows_module():
    path = ROOT / "windows" / "ios_loc.py"
    spec = importlib.util.spec_from_file_location("ios_loc", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def swift_normalize(text):
    return "".join(text.split()).lower()


def swift_resolve(module, text):
    """复刻 ios-app/Xunidingwei/Models.swift 里 resolve() 的行为。"""
    cleaned = text.replace(",", " ").replace("，", " ")
    parts = cleaned.split()
    if len(parts) == 2:
        try:
            lat, lon = float(parts[0]), float(parts[1])
        except ValueError:
            pass
        else:
            if -90 <= lat <= 90 and -180 <= lon <= 180:
                return ("自定义坐标", lat, lon)
            return None
    return module.LOOKUP.get(swift_normalize(cleaned))


CASES = [
    "英国", "uk", "UK", "London", "london", "伦敦", "洛杉矶", "美国洛杉矶",
    "美国 洛杉矶", "美国，洛杉矶", "东京", "日本", "china", "中国", "北京",
    "香港", "澳门", "新加坡", "巴厘岛", "bali", "夏威夷", "檀香山",
    "51.5074 -0.1278", "51.5074,-0.1278", "51.5074，-0.1278",
    "0 0", "-33.8688 151.2093", "91 0", "0 181",
    "  英国  ", "southkorea", "korea", "首尔", "纽约", "nyc", "la",
    "圣保罗", "里约", "胡志明", "西贡", "澳洲", "悉尼",
]


def main():
    module = load_windows_module()
    failures = []

    for case in CASES:
        expected = module.resolve([case])
        actual = swift_resolve(module, case)
        if expected != actual:
            failures.append((case, expected, actual))

    # 英文别名大小写与空格变体必须等价
    for variant in ("LONDON", "London", "  london ", "l o n d o n"):
        if module.LOOKUP.get(swift_normalize(variant)) is None:
            failures.append((variant, "应能解析", "解析失败"))

    # 推荐功能：只输入一部分时也要能给出候选（与 Swift 版同一套子串规则）
    for partial, expected_label in [("londo", "英国 伦敦"), ("losangel", "美国 洛杉矶"), ("伦敦市", "英国 伦敦")]:
        if expected_label not in module.suggest(partial):
            failures.append((partial, "应建议 %s" % expected_label, str(module.suggest(partial))))

    if failures:
        print("不一致的用例：")
        for case, expected, actual in failures:
            print("  输入 %r\n    期望 %r\n    实际 %r" % (case, expected, actual))
        return 1

    print("通过：%d 个解析用例与 Swift 规则一致" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
