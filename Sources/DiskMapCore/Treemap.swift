import Foundation
import CoreGraphics

public struct MapItem: Sendable {
    public let id: Int
    public let weight: Double
    public init(id: Int, weight: Double) { self.id = id; self.weight = weight }
}
public struct MapTile: Sendable {
    public let id: Int
    public let rect: CGRect
}

public enum TreemapLayout {
    /// Squarified rows. Stable ID breaks ties so identical inputs never shuffle.
    public static func layout(_ items: [MapItem], in bounds: CGRect) -> [MapTile] {
        let positive = items.filter { $0.weight > 0 && $0.weight.isFinite }.sorted {
            $0.weight == $1.weight ? $0.id < $1.id : $0.weight > $1.weight
        }
        let total = positive.reduce(0) { $0 + $1.weight }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        let scale = bounds.width * bounds.height / total
        var remaining = bounds, row: [(Int, Double)] = [], result: [MapTile] = []
        func worst(_ values: [(Int, Double)], _ side: Double) -> Double {
            guard let first = values.first, side > 0 else { return .infinity }
            let sum = values.reduce(0) { $0 + $1.1 }
            let minimum = values.map(\.1).min() ?? first.1
            let maximum = values.map(\.1).max() ?? first.1
            return max(side * side * maximum / (sum * sum), sum * sum / (side * side * minimum))
        }
        func commitRow() {
            guard !row.isEmpty else { return }
            let area = row.reduce(0) { $0 + $1.1 }
            if remaining.width >= remaining.height {
                let width = min(remaining.width, area / remaining.height)
                var y = remaining.minY
                for (offset, pair) in row.enumerated() {
                    let height = offset == row.count - 1 ? remaining.maxY - y : pair.1 / width
                    result.append(MapTile(id: pair.0, rect: CGRect(x: remaining.minX, y: y, width: width, height: max(0, height))))
                    y += height
                }
                remaining.origin.x += width; remaining.size.width = max(0, remaining.width - width)
            } else {
                let height = min(remaining.height, area / remaining.width)
                var x = remaining.minX
                for (offset, pair) in row.enumerated() {
                    let width = offset == row.count - 1 ? remaining.maxX - x : pair.1 / height
                    result.append(MapTile(id: pair.0, rect: CGRect(x: x, y: remaining.minY, width: max(0, width), height: height)))
                    x += width
                }
                remaining.origin.y += height; remaining.size.height = max(0, remaining.height - height)
            }
            row.removeAll(keepingCapacity: true)
        }
        for item in positive {
            let next = (item.id, item.weight * scale)
            let side = min(remaining.width, remaining.height)
            if !row.isEmpty && worst(row + [next], side) > worst(row, side) { commitRow() }
            row.append(next)
        }
        commitRow()
        return result
    }
}
