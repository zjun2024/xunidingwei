import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// 地图选点。
///
/// 交互与 zjq 插件保持一致，全部基于系统 MapKit：
/// 点地图取坐标、搜索地点、反查中文地址。
struct MapPickerView: View {
    @Environment(\.presentationMode) private var presentationMode

    let onPick: (LocationTarget) -> Void

    @StateObject private var bridge = MapBridge()
    @State private var picked: CLLocationCoordinate2D?
    @State private var address = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isGeocoding = false
    @State private var notice: String?

    private let defaultCenter = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                mapArea
                detailBar
                if !results.isEmpty {
                    resultList
                }
            }
            .navigationTitle("地图选点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("使用") { confirm() }
                        .disabled(picked == nil)
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "搜索地点、地址或地标")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { newValue in
                if newValue.isEmpty { results = [] }
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 地图

    private var mapArea: some View {
        ZStack(alignment: .bottomTrailing) {
            MapCanvas(bridge: bridge, picked: $picked, initialCenter: defaultCenter) { coordinate in
                pick(coordinate)
            }

            VStack(spacing: 10) {
                mapButton("location.fill") {
                    bridge.focus(on: picked ?? defaultCenter)
                }
                mapButton("plus.magnifyingglass") { bridge.zoom(by: 0.5) }
                mapButton("minus.magnifyingglass") { bridge.zoom(by: 2) }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mapButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 详情

    private var detailBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: picked == nil ? "hand.tap" : "mappin.circle.fill")
                    .foregroundColor(picked == nil ? .secondary : .accentColor)
                Text(titleText)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
            }

            if let picked {
                Text(coordinateText(picked))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var titleText: String {
        if picked == nil { return "点一下地图选择位置" }
        if isGeocoding { return "正在识别地址…" }
        return address.isEmpty ? "已选位置" : address
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - 搜索结果

    private var resultList: some View {
        List(results, id: \.self) { item in
            Button {
                select(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "未命名地点")
                        .foregroundColor(.primary)
                    if let subtitle = item.placemark.title, subtitle != item.name {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 220)
    }

    // MARK: - 动作

    private func pick(_ coordinate: CLLocationCoordinate2D) {
        picked = coordinate
        address = ""
        notice = nil
        reverseGeocode(coordinate)
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        isGeocoding = true
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        CLGeocoder().reverseGeocodeLocation(location,
                                            preferredLocale: Locale(identifier: "zh_CN")) { placemarks, error in
            isGeocoding = false
            if let error {
                notice = "地址识别失败：\(error.localizedDescription)"
                return
            }
            guard let placemark = placemarks?.first else {
                address = "未知地点"
                return
            }
            address = Self.format(placemark)
        }
    }

    private static func format(_ placemark: CLPlacemark) -> String {
        let candidates = [placemark.country,
                          placemark.administrativeArea,
                          placemark.locality,
                          placemark.subLocality,
                          placemark.thoroughfare,
                          placemark.name]
        var parts: [String] = []
        for case let value? in candidates where !value.isEmpty {
            if !parts.contains(value) { parts.append(value) }
        }
        return parts.isEmpty ? "未知地点" : parts.joined(separator: " ")
    }

    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }

        notice = nil
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = keyword
        request.region = bridge.currentRegion
            ?? MKCoordinateRegion(center: defaultCenter,
                                  latitudinalMeters: 400_000,
                                  longitudinalMeters: 400_000)

        MKLocalSearch(request: request).start { response, error in
            if let error {
                notice = "搜索失败：\(error.localizedDescription)"
                results = []
                return
            }
            results = Array((response?.mapItems ?? []).prefix(12))
            if results.isEmpty { notice = "没有找到「\(keyword)」" }
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        results = []
        query = ""
        pick(coordinate)
        bridge.focus(on: coordinate)
    }

    private func confirm() {
        guard let picked else { return }
        let label = address.isEmpty ? "地图选点" : address
        onPick(LocationTarget(label: label,
                              latitude: picked.latitude,
                              longitude: picked.longitude))
        presentationMode.wrappedValue.dismiss()
    }
}

/// 持有底层 MKMapView，供 SwiftUI 触发程序化移动。
///
/// 直接双向同步 region 会和用户拖动打架，所以只在按钮和搜索时单向下发。
final class MapBridge: ObservableObject {
    weak var mapView: MKMapView?

    var currentRegion: MKCoordinateRegion? { mapView?.region }

    func focus(on coordinate: CLLocationCoordinate2D) {
        guard let mapView else { return }
        mapView.setRegion(MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 1_500,
                                            longitudinalMeters: 1_500),
                          animated: true)
    }

    func zoom(by factor: Double) {
        guard let mapView else { return }
        var region = mapView.region
        region.span.latitudeDelta *= factor
        region.span.longitudeDelta *= factor
        mapView.setRegion(region, animated: true)
    }
}

private struct MapCanvas: UIViewRepresentable {
    let bridge: MapBridge
    @Binding var picked: CLLocationCoordinate2D?
    let initialCenter: CLLocationCoordinate2D
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.pointOfInterestFilter = .includingAll
        mapView.setRegion(MKCoordinateRegion(center: initialCenter,
                                             latitudinalMeters: 80_000,
                                             longitudinalMeters: 80_000),
                          animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)
        bridge.mapView = mapView
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.onTap = onTap

        guard let coordinate = picked else {
            mapView.removeAnnotations(mapView.annotations)
            context.coordinator.pin = nil
            return
        }

        if let pin = context.coordinator.pin {
            pin.coordinate = coordinate
        } else {
            let pin = MKPointAnnotation()
            pin.coordinate = coordinate
            context.coordinator.pin = pin
            mapView.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onTap: (CLLocationCoordinate2D) -> Void
        var pin: MKPointAnnotation?

        init(onTap: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            onTap(mapView.convert(point, toCoordinateFrom: mapView))
        }
    }
}
