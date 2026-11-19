import Foundation

// ---- SwiftUI / UIKit 桩（只保留 LocSimStore 用到的部分） ----
protocol ObservableObject: AnyObject {}

@propertyWrapper
struct Published<Value> {
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

extension Array {
    mutating func remove(atOffsets: IndexSet) {}
}
