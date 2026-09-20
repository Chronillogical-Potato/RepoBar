import AppKit

@MainActor
enum RateLimitStatusIconRenderer {
    private struct RenderedQuota {
        let rest: String
        let graphQL: String
        let image: NSImage
    }

    private static var cached: RenderedQuota?

    static func makeIcon(restText: String, graphQLText: String) -> NSImage {
        if let cached, cached.rest == restText, cached.graphQL == graphQLText {
            return cached.image
        }

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.75)
        ]
        let rest = NSAttributedString(string: restText, attributes: valueAttributes)
        let graphQL = NSAttributedString(string: graphQLText, attributes: valueAttributes)
        let labelWidth: CGFloat = 9
        let width = ceil(max(rest.size().width, graphQL.size().width)) + labelWidth + 2
        let image = NSImage(size: NSSize(width: width, height: 22))
        image.lockFocus()
        NSAttributedString(string: "R", attributes: labelAttributes).draw(at: NSPoint(x: 0, y: 11))
        rest.draw(at: NSPoint(x: labelWidth, y: 11))
        NSAttributedString(string: "G", attributes: labelAttributes).draw(at: NSPoint(x: 0, y: 1))
        graphQL.draw(at: NSPoint(x: labelWidth, y: 1))
        image.unlockFocus()
        image.isTemplate = true
        self.cached = RenderedQuota(rest: restText, graphQL: graphQLText, image: image)
        return image
    }
}
