import AppKit

/// Renders the menu-bar metrics as a single image, Stats-app style: each metric is a column
/// with a small uppercase label stacked above its value, columns laid out side by side.
/// Produced as a template image so the menu bar tints it for light/dark automatically.
enum MenuBarRenderer {
    static func image(metrics: [MenuMetric], scale: CGFloat = 1) -> NSImage? {
        guard !metrics.isEmpty else { return nil }

        let labelFont = NSFont.systemFont(ofSize: 8.05 * scale, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11.4 * scale, weight: .semibold)
        let labelAttrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.black]

        struct Column { let label: NSAttributedString; let value: NSAttributedString; let width: CGFloat }
        let columns: [Column] = metrics.map {
            let label = NSAttributedString(string: $0.label, attributes: labelAttrs)
            let value = NSAttributedString(string: $0.value, attributes: valueAttrs)
            return Column(label: label, value: value, width: ceil(max(label.size().width, value.size().width)))
        }

        let labelH = ceil(NSAttributedString(string: "CPU", attributes: labelAttrs).size().height)
        let valueH = ceil(NSAttributedString(string: "0%", attributes: valueAttrs).size().height)
        let rowGap: CGFloat = 0
        let colGap: CGFloat = 5.75 * scale
        let hPad: CGFloat = 1 * scale
        let totalH = labelH + rowGap + valueH
        let totalW = columns.reduce(0) { $0 + $1.width } + colGap * CGFloat(columns.count - 1) + hPad * 2

        let image = NSImage(size: NSSize(width: ceil(totalW), height: ceil(totalH)), flipped: false) { _ in
            // Non-flipped coords: y = 0 is the bottom, so the value sits below and the label above.
            var x = hPad
            for column in columns {
                let valueX = x + (column.width - column.value.size().width) / 2
                let labelX = x + (column.width - column.label.size().width) / 2
                column.value.draw(at: NSPoint(x: valueX, y: 0))
                column.label.draw(at: NSPoint(x: labelX, y: valueH + rowGap))
                x += column.width + colGap
            }
            return true
        }
        image.isTemplate = (scale == 1)
        return image
    }
}
