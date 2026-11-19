# 寻定位（Xunidingwei）

Windows 版 iOS 改定位工具的移植版：iOS App 直接在巨魔（TrollStore）手机上改定位，无需电脑。

## 目标环境

- iOS 16.6.1 + TrollStore（巨魔）
- 部署目标 iOS 15.0
- 安装方式：TrollStore 安装仓库打包的 ipa（**必须用仓库的 ipa**，重签名会丢权限）

## 架构

```
ios-app/
  Xunidingwei/
    Engine/
      LocSimEngine.swift      私有 API CLSimulationManager 驱动 locationd
      LocSimStore.swift       全局状态、历史、保活联动
      KeepAlive.swift         无声音频后台保活
      LocationVerifier.swift  CLLocationManager 读回坐标做实测校验
      DiagnosticLog.swift     os_log 出口（subsystem com.zjun2024.xunidingwei）
    Private/CLSimulationManager.h   私有类声明（只有声明，实现由系统提供）
    Bridging/Xunidingwei-Bridging-Header.h
    Views/                    含 MapPickerView（MapKit 选点）
windows/
  ios_loc.py                  原 Windows 工具（pymobiledevice3）
  grab_log.py                 一键抓手机日志
tools/
  logic-tests/run.sh          Linux 上用桩编译真实引擎逻辑
```

## 关键结论（踩过的坑，勿重犯）

1. **不能用协议元类型转换实例化系统私有类**
   `NSClassFromString(x) as? SomeProtocol.Type` 只对显式声明遵循该协议的类型成立，
   系统私有类永远返回 nil。正确做法：ObjC 头文件声明该类，Swift 直接用真实类型。

2. **`platform-application` 会让沙盒收紧**
   TrollStore 官方文档明说。必须同时补 `no-sandbox` / `container-manager` /
   `system-application`，否则 locationd 的 XPC 请求被静默丢弃
   （调用全成功、坐标不变）。

3. **调用成功 ≠ 生效**
   唯一可靠判定：用 `CLLocationManager` 读回系统坐标与模拟值比对（LocationVerifier）。
   2026-11 真机实测：修正后系统返回坐标与设置值相差 0 米，高德/苹果地图均生效。

4. **Linux 环境无 ObjC 互操作**
   本地 `swiftc` 无法验证 `NSSelectorFromString`/`responds(to:)`/`perform`。
   引擎用 `#if canImport(ObjectiveC)` 分流：iOS 走真实类型，Linux 测试走空实现。

## 构建与验证

```bash
# 本地全套校验（Linux 可用）
python3 tools/gen_locations.py --check   # 153 城市一致性
python3 tools/test_parity.py             # 42 个解析用例
SWIFTC=swiftc bash tools/logic-tests/run.sh
swiftc -frontend -parse $(find ios-app/Xunidingwei -name '*.swift')
```

推送 main 后 GitHub Actions 真机编译并发布 release。

## 抓日志（排障）

电脑连手机，双击 `windows/grab-log-windows.bat`，手机上操作一次后 Ctrl+C，
日志存到 `windows/xunidingwei-log.txt`。

也可手动：`pymobiledevice3 syslog live --subsystem com.zjun2024.xunidingwei`
