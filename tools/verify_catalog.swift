// 地点解析逻辑自检（纯 Foundation，可在任意平台运行）。
//
// 用法:
//   swiftc -use-ld=lld tools/verify_catalog.swift \
//          ios-app/Xunidingwei/Models.swift \
//          ios-app/Xunidingwei/Generated/LocationData.swift -o verify && ./verify
//
// 校验 Models.swift 的解析结果与 windows/ios_loc.py 一致。
import Foundation

var failures = 0

func check(_ input: String, _ expected: (String, Double, Double)?) {
    let got = LocationCatalog.shared.resolve(input)
    let gotTuple = got.map { ($0.label, $0.latitude, $0.longitude) }
    var ok = false
    switch (gotTuple, expected) {
    case (nil, nil):
        ok = true
    case let (actual?, want?):
        ok = actual.0 == want.0
            && abs(actual.1 - want.1) < 1e-9
            && abs(actual.2 - want.2) < 1e-9
    default:
        ok = false
    }
    if !ok {
        failures += 1
        print("FAIL \(input): 实际 \(String(describing: gotTuple)) 期望 \(String(describing: expected))")
    }
}

let catalog = LocationCatalog.shared
print("地点总数: \(catalog.places.count)")

check("英国", ("英国 伦敦", 51.5074, -0.1278))
check("uk", ("英国 伦敦", 51.5074, -0.1278))
check("UK", ("英国 伦敦", 51.5074, -0.1278))
check("london", ("英国 伦敦", 51.5074, -0.1278))
check("伦敦", ("英国 伦敦", 51.5074, -0.1278))
check("洛杉矶", ("美国 洛杉矶", 34.0522, -118.2437))
check("美国洛杉矶", ("美国 洛杉矶", 34.0522, -118.2437))
check("美国 洛杉矶", ("美国 洛杉矶", 34.0522, -118.2437))
check("美国，洛杉矶", ("美国 洛杉矶", 34.0522, -118.2437))
check("东京", ("日本 东京", 35.6762, 139.6503))
check("香港", ("香港", 22.3193, 114.1694))
check("新加坡", ("新加坡", 1.3521, 103.8198))
check("51.5074 -0.1278", ("自定义坐标", 51.5074, -0.1278))
check("51.5074,-0.1278", ("自定义坐标", 51.5074, -0.1278))
check("0 0", ("自定义坐标", 0, 0))
check("91 0", nil)
check("0 181", nil)
check("不存在的地方", nil)

if !catalog.suggest("londo").contains("英国 伦敦") {
    failures += 1
    print("FAIL suggest(londo) 应包含 英国 伦敦")
}

let groups = catalog.groupedPlaces()
if groups.isEmpty || groups.first?.countries.isEmpty != false {
    failures += 1
    print("FAIL 分组浏览为空")
}

print(failures == 0 ? "全部通过" : "失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)
