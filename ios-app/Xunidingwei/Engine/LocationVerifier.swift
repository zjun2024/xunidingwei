import CoreLocation
import Foundation

/// 实测校验：用 CLLocationManager 读回系统当前给出的坐标，
/// 与模拟值比较，判断模拟是否真的被 locationd 接受。
///
/// 这是唯一可靠的判定方式——私有 API 调用成功并不代表系统采纳了坐标，
/// locationd 的 XPC 请求可能被静默丢弃。
final class LocationVerifier: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Verdict {
        case pending
        case matched
        case notApplied(actual: CLLocationCoordinate2D?)
        case failed(String)
    }

    @Published private(set) var verdict: Verdict = .pending

    private let manager = CLLocationManager()
    private var expected: CLLocationCoordinate2D?

    /// 两个坐标是否足够接近（约 1 公里内即认为命中）。
    private static let toleranceMeters: CLLocationDistance = 1000

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func verify(expected target: LocationTarget) {
        expected = CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        verdict = .pending
        DiagnosticLog.step("验证开始，期望坐标 \(target.coordinateText)，授权状态=\(manager.authorizationStatus.rawValue)")

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            verdict = .failed("定位权限被拒绝，请到 设置 → 隐私与安全性 → 定位服务 里允许「寻定位」")
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if expected != nil { manager.requestLocation() }
        case .denied, .restricted:
            if expected != nil {
                verdict = .failed("定位权限被拒绝，请到 设置 → 隐私与安全性 → 定位服务 里允许「寻定位」")
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let expected, let actual = locations.last?.coordinate else { return }
        let from = CLLocation(latitude: expected.latitude, longitude: expected.longitude)
        let to = CLLocation(latitude: actual.latitude, longitude: actual.longitude)
        let distance = from.distance(from: to)
        DiagnosticLog.step(String(format: "系统返回坐标 %.6f, %.6f，与期望相差 %.0f 米",
                                  actual.latitude, actual.longitude, distance))
        verdict = distance <= Self.toleranceMeters ? .matched : .notApplied(actual: actual)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiagnosticLog.failure("读取系统坐标失败：\(error.localizedDescription)")
        verdict = .failed(error.localizedDescription)
    }
}
