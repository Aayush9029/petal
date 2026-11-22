import CoreGraphics

enum RouterFlowLayout {
    static let nodeHeight: CGFloat = 46
    static let rowSpacing: CGFloat = 10
    static let spineGap: CGFloat = 36
    static let hubSize: CGFloat = 40
    static let hubSpacing: CGFloat = 18
    static let cornerRadius: CGFloat = 8

    static var headerHeight: CGFloat { hubSize * 2 + hubSpacing * 2 }
    static var routerTop: CGFloat { hubSize + hubSpacing }
    static var routerBottom: CGFloat { routerTop + hubSize }

    static func rows(slots: Int) -> Int {
        (slots + 1) / 2
    }

    static func height(slots: Int) -> CGFloat {
        let rows = rows(slots: slots)
        return headerHeight + CGFloat(rows) * nodeHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
    }

    static func midY(slot: Int) -> CGFloat {
        headerHeight + CGFloat(slot / 2) * (nodeHeight + rowSpacing) + nodeHeight / 2
    }

    static func isLeft(slot: Int) -> Bool {
        slot.isMultiple(of: 2)
    }

    static func columnWidth(in width: CGFloat) -> CGFloat {
        (width - spineGap) / 2
    }

    static func edge(slot: Int, width: CGFloat) -> CGPoint {
        let column = columnWidth(in: width)
        let x = isLeft(slot: slot) ? column : column + spineGap
        return CGPoint(x: x, y: midY(slot: slot))
    }

    static func activePath(slot: Int, width: CGFloat) -> CGPath {
        let spineX = width / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: spineX, y: hubSize))
        path.addLine(to: CGPoint(x: spineX, y: routerTop))
        path.addPath(routePath(slot: slot, width: width))
        return path
    }

    static func routePath(slot: Int, width: CGFloat) -> CGPath {
        let spineX = width / 2
        let end = edge(slot: slot, width: width)
        let radius = min(cornerRadius, abs(end.x - spineX))
        let direction: CGFloat = end.x < spineX ? -1 : 1
        let path = CGMutablePath()
        path.move(to: CGPoint(x: spineX, y: routerBottom))
        path.addLine(to: CGPoint(x: spineX, y: end.y - radius))
        path.addQuadCurve(to: CGPoint(x: spineX + direction * radius, y: end.y), control: CGPoint(x: spineX, y: end.y))
        path.addLine(to: end)
        return path
    }
}
