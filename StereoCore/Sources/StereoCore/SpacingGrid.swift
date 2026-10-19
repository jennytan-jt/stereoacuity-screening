/// Answers "is any stored point closer than `spacing` to this one?" without
/// checking every stored point.
///
/// The plane is divided into square cells `spacing` wide, and each point is
/// filed under the cell it falls in. Any point closer than `spacing` to a
/// query must then sit in the query's own cell or one of its 8 neighbors,
/// so a query looks at a handful of points instead of all of them. That
/// turns dot generation from quadratic in the dot count (each new dot
/// against every existing one) into roughly linear.
///
/// The distance test is written exactly as the brute-force version wrote
/// it (stored minus candidate, squared, summed), so switching to the grid
/// changes which points get *compared*, never the answer for any pair.
struct SpacingGrid {
    /// A cell's integer coordinates. A struct with two `Int`s gets `Hashable`
    /// for free once declared, which is all a dictionary key needs.
    private struct Cell: Hashable {
        let column: Int
        let row: Int
    }

    private let spacing: Double
    private let spacingSquared: Double
    /// Only cells that hold points get an entry; empty space costs nothing.
    private var cells: [Cell: [(x: Double, y: Double)]] = [:]

    init(spacing: Double) {
        precondition(spacing > 0, "spacing must be positive")
        self.spacing = spacing
        self.spacingSquared = spacing * spacing
    }

    private func cell(x: Double, y: Double) -> Cell {
        Cell(column: Int((x / spacing).rounded(.down)), row: Int((y / spacing).rounded(.down)))
    }

    mutating func insert(x: Double, y: Double) {
        // `default:` creates an empty array the first time a cell is used,
        // and the append mutates the stored array in place.
        cells[cell(x: x, y: y), default: []].append((x, y))
    }

    /// Whether any stored point is strictly closer than `spacing` to (x, y).
    func hasPoint(near x: Double, _ y: Double) -> Bool {
        let center = cell(x: x, y: y)
        for row in (center.row - 1)...(center.row + 1) {
            for column in (center.column - 1)...(center.column + 1) {
                guard let points = cells[Cell(column: column, row: row)] else { continue }
                for point in points {
                    let dx = point.x - x
                    let dy = point.y - y
                    if dx * dx + dy * dy < spacingSquared { return true }
                }
            }
        }
        return false
    }
}
