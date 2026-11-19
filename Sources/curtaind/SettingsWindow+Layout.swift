import AppKit
import CurtainKit

extension SettingsWindowController {
    func page(views: [NSView], spacing: CGFloat) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = spacing
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in views {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let page = NSView()
        page.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            stack.topAnchor.constraint(equalTo: page.topAnchor),
            stack.bottomAnchor.constraint(equalTo: page.bottomAnchor, constant: -16),
        ])
        return page
    }

    func card(containing rows: [NSView]) -> CurtainCardView {
        let card = CurtainCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        for (index, row) in rows.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(CurtainDividerView())
                stack.arrangedSubviews.last?.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        card.contentView.addSubview(stack)
        pin(stack, to: card.contentView)
        return card
    }

    func twoColumnRow(_ left: NSView, _ right: NSView) -> NSView {
        let row = NSStackView(views: [left, right])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 18
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        return row
    }

    func diagnosticRow(title: String, value: String) -> NSView {
        let valueLabel = NSTextField(labelWithString: value)
        return diagnosticRow(title: title, valueView: valueLabel)
    }

    func diagnosticRow(title: String, valueView: NSTextField) -> NSView {
        let titleLabel = CurtainTheme.label(
            title,
            size: 10.5,
            color: CurtainTheme.secondaryInk
        )
        valueView.font = .monospacedSystemFont(ofSize: 10.5, weight: .medium)
        valueView.textColor = CurtainTheme.ink
        valueView.alignment = .right
        valueView.maximumNumberOfLines = 1
        let row = CurtainTheme.stack(
            [titleLabel, valueView],
            orientation: .horizontal,
            spacing: 16,
            alignment: .centerY
        )
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueView.setContentHuggingPriority(.required, for: .horizontal)
        row.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 32),
        ])
        let container = NSView()
        container.addSubview(row)
        pin(row, to: container)
        return container
    }

    func pin(_ child: NSView, to parent: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }
}
