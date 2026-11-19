import CoreLocation
import Foundation

/// 从真实系统采集检测所需的原始数据，再交给 TamperDetector 判定。
/// 采集与判定分离：判定是纯函数可测，采集只能在真机跑。
final class EnvironmentProbe: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var samples: [LocationSample] = []
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var latestText: String = "尚未获取到定位"

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startSampling() {
        manager.startUpdatingLocation()
    }

    func stopSampling() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let sample = LocationSample(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            altitude: location.altitude,
            speed: location.speed,
            course: location.course,
            timestamp: location.timestamp,
            isSimulatedBySoftware: location.sourceInformation?.isSimulatedBySoftware,
            isProducedByAccessory: location.sourceInformation?.isProducedByAccessory
        )
        samples.append(sample)
        if samples.count > 20 { samples.removeFirst() }

        latestText = String(format: "%.6f, %.6f", sample.latitude, sample.longitude)
        evaluate()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        latestText = "定位失败：" + error.localizedDescription
    }

    // MARK: - 判定

    func evaluate() {
        let tzHours = Double(TimeZone.current.secondsFromGMT) / 3600.0
        var all = TamperDetector.checkLocation(samples, deviceTimeZoneOffsetHours: tzHours)
        all += TamperDetector.checkInjection(collectInjectionEnvironment())
        findings = all
    }

    /// 通过 sysctl 读取 P_TRACED 标志判断是否被调试。
    static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    /// 采集进程环境快照。
    private func collectInjectionEnvironment() -> InjectionEnvironment {
        var paths: [String] = []
        for i in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(i) {
                paths.append(String(cString: name))
            }
        }

        let env = ProcessInfo.environment
        let traced = EnvironmentProbe.isDebuggerAttached

        let suspicious = ["/var/jb/bin/sh", "/usr/bin/sbinpack", "/Library/MobileSubstrate"]
            .filter { FileManager.default.fileExists(atPath: $0) }

        return InjectionEnvironment(
            dyldImagePaths: paths,
            environment: env,
            isDebuggerAttached: traced,
            existingSuspiciousPaths: suspicious,
            hostHasSimulationEntitlement: EntitlementProbe.hasLocationSimulationEntitlement
        )
    }
}
