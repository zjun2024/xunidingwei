#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取「寻定位」的运行日志。

用法（Windows，手机用 USB 连电脑）：
    双击 grab-log-windows.bat

日志会保存到本文件同目录下的 xunidingwei-log.txt，
抓取过程中请在手机上点一次「验证是否生效」，这样日志里才会有对比结果。

只依赖 pymobiledevice3，和 ios_loc.py 用的是同一个工具。
"""

import os
import subprocess
import sys
import time

PMD3 = [sys.executable, "-m", "pymobiledevice3"]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_FILE = os.path.join(HERE, "xunidingwei-log.txt")

# 我们的 App 只往这个 subsystem 写日志，过滤后体积很小。
SUBSYSTEM = "com.zjun2024.xunidingwei"

# 额外关注 locationd 自己的记录：模拟请求被拒绝时通常在这里留痕。
EXTRA_MATCH = ["CLSimulation", "SimulationManager", "simulatelocation"]


def tool_ready():
    try:
        import importlib.util

        return importlib.util.find_spec("pymobiledevice3") is not None
    except Exception:
        return False


def device_connected():
    try:
        done = subprocess.run(PMD3 + ["usbmux", "list"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        out = done.stdout.decode("utf-8", errors="replace")
        return "DeviceClass" in out or '"DeviceName"' in out
    except Exception:
        return False


def main():
    print("=" * 56)
    print(" 寻定位 - 运行日志抓取")
    print("=" * 56)

    if not tool_ready():
        print("\n还没安装 pymobiledevice3，请先在命令行运行：")
        print("   py -m pip install -U pymobiledevice3")
        return 1

    if not device_connected():
        print("\n没检测到手机。请确认：")
        print("   1. 数据线已连接")
        print("   2. 手机上点了「信任此电脑」")
        print("   3. 手机已解锁")
        return 1

    print("\n已连接手机。")
    print("\n接下来请这样操作：")
    print("   1. 打开「寻定位」，选一个离你很远的地点（例如伦敦）")
    print("   2. 点「验证是否生效」")
    print("   3. 等 10 秒左右，然后回到这里按 Ctrl+C 结束")
    print("\n正在开始抓日志…\n")

    cmd = PMD3 + [
        "syslog", "live",
        "--subsystem", SUBSYSTEM,
        "--out", OUT_FILE,
    ]

    try:
        # 日志同时写文件和屏幕，方便用户当场看到
        subprocess.run(cmd, timeout=600)
    except KeyboardInterrupt:
        pass
    except subprocess.TimeoutExpired:
        print("\n抓取满 10 分钟，自动结束。")
    except Exception as exc:  # noqa: BLE001
        print("\n抓取失败：%s" % exc)

    # 再抓一次 locationd 侧的关键字记录：模拟请求被拒绝时通常在这里留痕。
    # live 是持续输出，用超时控制时长；超时属于正常结束。
    print("\n正在补充抓取 locationd 相关记录（约 20 秒）…")
    extra = []
    for keyword in EXTRA_MATCH:
        extra += ["--match", keyword]
    try:
        done = subprocess.run(
            PMD3 + ["syslog", "live"] + extra,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
        text = done.stdout.decode("utf-8", errors="replace")
    except subprocess.TimeoutExpired as exc:
        text = (exc.output or b"").decode("utf-8", errors="replace")
    except Exception:
        text = ""

    if text.strip():
        with open(OUT_FILE, "a", encoding="utf-8") as fh:
            fh.write("\n=== locationd 相关记录 ===\n" + text + "\n")

    print("\n" + "=" * 56)
    if os.path.exists(OUT_FILE) and os.path.getsize(OUT_FILE) > 0:
        print("日志已保存：")
        print("   " + OUT_FILE)
        print("\n把这个文件发给开发者即可定位问题。")
    else:
        print("没有抓到日志。可能是 App 没有产生新的定位操作，")
        print("或者日志已经被系统轮转掉，请重试一次并在手机上点「验证是否生效」。")
    print("=" * 56)
    return 0


if __name__ == "__main__":
    sys.exit(main())
