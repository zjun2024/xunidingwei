import Foundation

/// 一个可定位的地点。
struct Place {
    let group: String
    let country: String
    let city: String
    let latitude: Double
    let longitude: Double
    let countryNames: [String]
    let cityNames: [String]

    /// 显示名，和 Windows 版一致：城市名与国家同名时只显示一次。
    var label: String {
        city == country ? city : country + " " + city
    }

    var coordinateText: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}

/// 解析出来的定位目标。
struct LocationTarget: Equatable {
    let label: String
    let latitude: Double
    let longitude: Double

    var coordinateText: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}

/// 地点库：负责把用户输入解析成坐标，逻辑与 windows/ios_loc.py 保持一致。
final class LocationCatalog {
    static let shared = LocationCatalog()

    let places: [Place]
    private var lookup: [String: LocationTarget] = [:]

    init(places: [Place] = LocationData.places) {
        self.places = places
        buildLookup()
    }

    /// 去掉所有空白字符并转小写，中英文都能匹配。
    static func normalize(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace }).lowercased()
    }

    private struct CountryBucket {
        let country: Place
        var cities: [Place]
    }

    private func buildLookup() {
        var grouped: [CountryBucket] = []
        var indexByCountry: [String: Int] = [:]

        for place in places {
            let key = place.group + "|" + place.country
            if let index = indexByCountry[key] {
                grouped[index].cities.append(place)
            } else {
                indexByCountry[key] = grouped.count
                grouped.append(CountryBucket(country: place, cities: [place]))
            }
        }

        func register(_ key: String, _ place: Place) {
            let normalized = Self.normalize(key)
            guard !normalized.isEmpty, lookup[normalized] == nil else { return }
            lookup[normalized] = LocationTarget(label: place.label,
                                                latitude: place.latitude,
                                                longitude: place.longitude)
        }

        // 顺序与 Python 版一致：先国家名（指向默认城市），再城市名，最后“国家+城市”。
        for entry in grouped {
            guard let defaultCity = entry.cities.first else { continue }
            for name in entry.country.countryNames {
                register(name, defaultCity)
            }
        }
        for entry in grouped {
            for place in entry.cities {
                for name in place.cityNames {
                    register(name, place)
                }
            }
        }
        for entry in grouped {
            for place in entry.cities {
                for countryName in entry.country.countryNames {
                    for cityName in place.cityNames {
                        register(countryName + cityName, place)
                    }
                }
            }
        }
    }

    /// 把用户输入解析成定位目标；解析不了返回 nil。
    func resolve(_ input: String) -> LocationTarget? {
        let text = input
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "，", with: " ")
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

        if parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) {
            guard (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
            return LocationTarget(label: "自定义坐标", latitude: lat, longitude: lon)
        }
        return lookup[Self.normalize(text)]
    }

    /// 找不到时给出名字相近的地点。
    func suggest(_ input: String, limit: Int = 8) -> [String] {
        let key = Self.normalize(input)
        guard !key.isEmpty else { return [] }

        var found: [String] = []
        for (name, target) in lookup {
            let longEnough = name.unicodeScalars.allSatisfy(\.isASCII)
                ? name.count >= 4
                : name.count >= 2
            if name.contains(key) || (longEnough && key.contains(name)) {
                if !found.contains(target.label) {
                    found.append(target.label)
                }
            }
        }
        return Array(found.prefix(limit))
    }

    struct CountrySection: Identifiable {
        let country: String
        let cities: [Place]
        var id: String { country }
    }

    struct GroupSection: Identifiable {
        let group: String
        let countries: [CountrySection]
        var id: String { group }
    }

    /// 按分组列出全部地点，用于“地点列表”页面。
    func groupedPlaces() -> [GroupSection] {
        var order: [String] = []
        var byGroup: [String: [String]] = [:]
        var byCountry: [String: [Place]] = [:]

        for place in places {
            if byGroup[place.group] == nil {
                order.append(place.group)
                byGroup[place.group] = []
            }
            if !(byGroup[place.group]?.contains(place.country) ?? false) {
                byGroup[place.group]?.append(place.country)
                byCountry[place.group + "|" + place.country] = []
            }
            byCountry[place.group + "|" + place.country]?.append(place)
        }

        return order.map { group in
            let countries = (byGroup[group] ?? []).map { country in
                CountrySection(country: country, cities: byCountry[group + "|" + country] ?? [])
            }
            return GroupSection(group: group, countries: countries)
        }
    }
}
