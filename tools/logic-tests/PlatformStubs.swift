// 用桩替代 UIKit/SwiftUI/CoreLocation/AVFoundation，验证逻辑与语法
import Foundation

// ---- CoreLocation 桩 ----
struct CLLocationCoordinate2D { var latitude: Double; var longitude: Double
  init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude } }
class CLLocation: NSObject {
  init(coordinate: CLLocationCoordinate2D, altitude: Double, horizontalAccuracy: Double,
       verticalAccuracy: Double, timestamp: Date) { super.init() }
}
