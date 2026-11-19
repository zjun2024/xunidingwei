# 寻定位

iPhone 虚拟定位，两种用法：

- **手机端**：装成 iPA，在手机上直接定位，不需要电脑（TrollStore / 巨魔环境）
- **电脑端**：Windows / Mac 用数据线连手机定位（Python）

两端共用同一份地点表（55 个国家/地区，153 个城市），输入规则完全一致。

---

## 一、手机端（iPA，无需电脑）

### 安装

1. 到 [Releases](../../releases) 下载 `Xunidingwei.ipa`
2. 传到手机（AirDrop / 文件 App / 爱思都行）
3. 用 **TrollStore** 打开该文件 → Install

> 必须安装这里的原始 iPA。用其他工具重新签名会丢掉
> `com.apple.locationd.simulation` 权限，App 能打开但定位不生效。

### 使用

- 顶部输入框输入 `英国`、`洛杉矶`、`美国洛杉矶`、`东京`、`51.5074 -0.1278`
- 或点右上角列表，按「地区 → 国家 → 城市」浏览，也可搜索
- 点「恢复真实定位」立即还原
- 锁屏或切到别的 App 后仍要保持定位时，打开「后台保活」
- 第一次用先看「环境自检」，三项都打勾就能用

### 环境要求

- iOS 15 及以上（系统里要有 `CLSimulationManager`）
- 定位服务已打开；iOS 16+ 还需要打开「开发者模式」

原理与排错见 [docs/技术方案.md](docs/技术方案.md)。

### 自己编译

```bash
brew install xcodegen ldid
cd ios-app
./build_ipa.sh          # 产物：ios-app/build/Xunidingwei.ipa
```

也可以直接推代码，GitHub Actions 会自动编译并发布到 Releases。

---

## 二、电脑端（Windows / Mac）

文件在 `windows/`：

| 文件 | 说明 |
| --- | --- |
| `ios_loc.py` | 主程序 |
| `ios-loc-windows.bat` | Windows 双击运行 |
| `新建 文本文档 (4).txt` | Windows 操作步骤 |

```bash
py -m pip install -U pymobiledevice3
py ios_loc.py            # 进入提问模式
py ios_loc.py set 英国
py ios_loc.py list
py ios_loc.py clear
```

定位在窗口运行期间保持，按 `Ctrl+C` 结束并恢复真实定位。

---

## 三、仓库结构

```
windows/                 电脑端工具（原版）
ios-app/                 手机端 iPA 工程
tools/gen_locations.py   从 ios_loc.py 生成 Swift 地点表
tools/test_parity.py     校验两端解析规则一致
docs/技术方案.md          手机端方案说明
.github/workflows/       自动编译并发布 iPA
```

修改地点只需改 `windows/ios_loc.py` 的 `DATA` 表，然后运行：

```bash
python3 tools/gen_locations.py      # 重新生成 Swift 地点表
python3 tools/test_parity.py        # 校验两端解析规则一致
bash tools/logic-tests/run.sh       # 用桩跑引擎与状态机（无需 Xcode）
```

`tools/logic-tests/` 用桩替代 UIKit、SwiftUI、CoreLocation、AVFoundation，
在没有 iOS SDK 的机器上也能真实执行引擎调用、错误提示、历史记录等逻辑。
