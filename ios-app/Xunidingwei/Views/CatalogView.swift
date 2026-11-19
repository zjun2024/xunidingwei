import SwiftUI

/// 地点列表：按分组 → 国家 → 城市浏览，支持搜索。
struct CatalogView: View {
    @Environment(\.presentationMode) private var presentationMode
    @State private var query = ""

    let onSelect: (Place) -> Void

    private let catalog = LocationCatalog.shared

    private var filtered: [Place] {
        let keyword = LocationCatalog.normalize(query)
        guard !keyword.isEmpty else { return catalog.places }
        return catalog.places.filter { place in
            let haystack = ([place.label] + place.cityNames + place.countryNames)
                .map(LocationCatalog.normalize)
                .joined(separator: "|")
            return haystack.contains(keyword)
        }
    }

    var body: some View {
        NavigationView {
            List {
                if query.isEmpty {
                    ForEach(catalog.groupedPlaces()) { section in
                        Section(header: Text(section.group)) {
                            ForEach(section.countries) { country in
                                NavigationLink(destination: CityListView(title: country.country,
                                                                          places: country.cities,
                                                                          onSelect: onSelect)) {
                                    HStack {
                                        Text(country.country)
                                        Spacer()
                                        Text("\(country.cities.count)")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有匹配的地点").font(.headline)
                        Text("试试国家名、城市名或英文名")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(filtered, id: \.label) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.label).foregroundColor(.primary)
                                Text(place.coordinateText)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索国家或城市")
            .navigationTitle("地点列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct CityListView: View {
    let title: String
    let places: [Place]
    let onSelect: (Place) -> Void

    var body: some View {
        List(places, id: \.label) { place in
            Button {
                onSelect(place)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.city).foregroundColor(.primary)
                    Text(place.coordinateText)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
