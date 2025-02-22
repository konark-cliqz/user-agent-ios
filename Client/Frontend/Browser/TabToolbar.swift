/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit
import Shared

protocol TabToolbarProtocol: AnyObject {
    var tabToolbarDelegate: TabToolbarDelegate? { get set }
    var tabsButton: TabsButton { get }
    var menuButton: ToolbarButton { get }
    var forwardButton: ToolbarButton { get }
    var backButton: ToolbarButton { get }
    var searchButton: ToolbarButton { get }
    var stopReloadButton: ToolbarButton { get }
    var actionButtons: [Themeable & UIButton] { get }

    func updateBackStatus(_ canGoBack: Bool)
    func updateForwardStatus(_ canGoForward: Bool)
    func updateReloadStatus(_ isLoading: Bool)
    func updatePageStatus(_ isWebPage: Bool)
    func updateTabCount(_ count: Int, animated: Bool)
    func privateModeBadge(visible: Bool)
}

protocol TabToolbarDelegate: AnyObject {
    func tabToolbarDidPressBack(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressForward(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidLongPressBack(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidLongPressForward(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressReload(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressStop(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressMenu(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressTabs(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidLongPressTabs(_ tabToolbar: TabToolbarProtocol, button: UIButton)
    func tabToolbarDidPressSearch(_ tabToolbar: TabToolbarProtocol, button: UIButton)
}

@objcMembers
open class TabToolbarHelper: NSObject {
    let toolbar: TabToolbarProtocol

    let ImageReload = UIImage.templateImageNamed("nav-refresh")
    let ImageStop = UIImage.templateImageNamed("nav-stop")

    var loading: Bool = false {
        didSet {
            if loading {
                toolbar.stopReloadButton.setImage(ImageStop, for: .normal)
                toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Stop", comment: "Accessibility Label for the tab toolbar Stop button")
            } else {
                toolbar.stopReloadButton.setImage(ImageReload, for: .normal)
                toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Reload", comment: "Accessibility Label for the tab toolbar Reload button")
            }
        }
    }

    fileprivate func setTheme(forButtons buttons: [Themeable]) {
        buttons.forEach { $0.applyTheme() }
    }

    init(toolbar: TabToolbarProtocol) {
        self.toolbar = toolbar
        super.init()

        toolbar.backButton.setImage(UIImage.templateImageNamed("nav-back"), for: .normal)
        toolbar.backButton.accessibilityLabel = NSLocalizedString("Back", comment: "Accessibility label for the Back button in the tab toolbar.")
        let longPressGestureBackButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressBack))
        toolbar.backButton.addGestureRecognizer(longPressGestureBackButton)
        toolbar.backButton.addTarget(self, action: #selector(didClickBack), for: .touchUpInside)

        toolbar.forwardButton.setImage(UIImage.templateImageNamed("nav-forward"), for: .normal)
        toolbar.forwardButton.accessibilityLabel = NSLocalizedString("Forward", comment: "Accessibility Label for the tab toolbar Forward button")
        let longPressGestureForwardButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressForward))
        toolbar.forwardButton.addGestureRecognizer(longPressGestureForwardButton)
        toolbar.forwardButton.addTarget(self, action: #selector(didClickForward), for: .touchUpInside)

        toolbar.stopReloadButton.setImage(UIImage.templateImageNamed("nav-refresh"), for: .normal)
        toolbar.stopReloadButton.accessibilityLabel = NSLocalizedString("Reload", comment: "Accessibility Label for the tab toolbar Reload button")
        toolbar.stopReloadButton.addTarget(self, action: #selector(didClickStopReload), for: .touchUpInside)

        toolbar.searchButton.setImage(UIImage.templateImageNamed("search"), for: .normal)
        toolbar.searchButton.addTarget(self, action: #selector(didClickSearch), for: .touchUpInside)

        toolbar.tabsButton.addTarget(self, action: #selector(didClickTabs), for: .touchUpInside)
        let longPressGestureTabsButton = UILongPressGestureRecognizer(target: self, action: #selector(didLongPressTabs))
        toolbar.tabsButton.addGestureRecognizer(longPressGestureTabsButton)

        toolbar.menuButton.contentMode = .center
        toolbar.menuButton.setImage(UIImage(named: "nav-menu")?.tinted(withColor: Theme.general.controlTint), for: .normal)
        toolbar.menuButton.accessibilityLabel = Strings.AppMenuButtonAccessibilityLabel
        toolbar.menuButton.addTarget(self, action: #selector(didClickMenu), for: .touchUpInside)
        toolbar.menuButton.accessibilityIdentifier = "TabToolbar.menuButton"
    }

    func didClickBack() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressBack(toolbar, button: toolbar.backButton)
    }

    func didLongPressBack(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressBack(toolbar, button: toolbar.backButton)
        }
    }

    func didClickTabs() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressTabs(toolbar, button: toolbar.tabsButton)
    }

    func didLongPressTabs(_ recognizer: UILongPressGestureRecognizer) {
        toolbar.tabToolbarDelegate?.tabToolbarDidLongPressTabs(toolbar, button: toolbar.tabsButton)
    }

    func didClickForward() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressForward(toolbar, button: toolbar.forwardButton)
    }

    func didLongPressForward(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            toolbar.tabToolbarDelegate?.tabToolbarDidLongPressForward(toolbar, button: toolbar.forwardButton)
        }
    }

    func didClickMenu() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressMenu(toolbar, button: toolbar.menuButton)
    }

    func didClickSearch() {
        toolbar.tabToolbarDelegate?.tabToolbarDidPressSearch(toolbar, button: toolbar.searchButton)
    }

    func didClickStopReload() {
        if loading {
            toolbar.tabToolbarDelegate?.tabToolbarDidPressStop(toolbar, button: toolbar.stopReloadButton)
        } else {
            toolbar.tabToolbarDelegate?.tabToolbarDidPressReload(toolbar, button: toolbar.stopReloadButton)
        }
    }

    func updateReloadStatus(_ isLoading: Bool) {
        loading = isLoading
    }
}

class ToolbarButton: UIButton {
    var selectedTintColor: UIColor!
    var unselectedTintColor: UIColor!
    var disabledTintColor: UIColor = {
        if #available(iOS 13.0, *) {
            return UIColor.systemGray
        } else {
            // Fallback on earlier versions
            return UIColor.lightGray
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        adjustsImageWhenHighlighted = false
        selectedTintColor = tintColor
        unselectedTintColor = tintColor
        imageView?.contentMode = .scaleAspectFit
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open var isHighlighted: Bool {
        didSet {
            self.tintColor = isHighlighted ? selectedTintColor : unselectedTintColor
        }
    }

    override open var isEnabled: Bool {
        didSet {
            self.tintColor = isEnabled ? unselectedTintColor : disabledTintColor
        }
    }

    override var tintColor: UIColor! {
        didSet {
            self.imageView?.tintColor = self.tintColor
        }
    }

}

extension ToolbarButton: Themeable {
    func applyTheme() {
        selectedTintColor = Theme.toolbarButton.selectedTint
        unselectedTintColor = Theme.browser.tint
        tintColor = isEnabled ? unselectedTintColor : disabledTintColor
        imageView?.tintColor = tintColor
    }
}

class TabToolbar: UIView {
    weak var tabToolbarDelegate: TabToolbarDelegate?

    let tabsButton = TabsButton()
    let menuButton = ToolbarButton()
    let forwardButton = ToolbarButton()
    let backButton = ToolbarButton()
    let searchButton = ToolbarButton()
    let actionButtons: [Themeable & UIButton]

    lazy var stopReloadButton = ToolbarButton()

    fileprivate let privateModeBadge = BadgeWithBackdrop(imageName: "privateModeBadge", backdropCircleColor: UIColor.ForgetMode)

    var helper: TabToolbarHelper?
    private let contentView = UIStackView()
    private let effectView: UIVisualEffectView = {
        let effectView = UIVisualEffectView()
        if #available(iOS 13.0, *) {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
        } else {
            // Fallback on earlier versions
            effectView.effect = UIBlurEffect(style: .light)
        }
        return effectView
    }()

    fileprivate override init(frame: CGRect) {
        actionButtons = [backButton, forwardButton, menuButton, searchButton, tabsButton]
        super.init(frame: frame)
        setupAccessibility()

        addSubview(effectView)

        addSubview(contentView)
        helper = TabToolbarHelper(toolbar: self)
        addButtons(actionButtons)

        privateModeBadge.add(toParent: contentView)

        contentView.axis = .horizontal
        contentView.distribution = .fillEqually
    }

    override func updateConstraints() {
        privateModeBadge.layout(onButton: tabsButton)

        contentView.snp.makeConstraints { make in
            make.leading.trailing.top.equalTo(self)
            make.bottom.equalTo(self.safeArea.bottom)
        }

        effectView.snp.makeConstraints { make in
            make.leading.trailing.top.bottom.equalTo(self)
        }

        super.updateConstraints()
    }

    private func setupAccessibility() {
        backButton.accessibilityIdentifier = "TabToolbar.backButton"
        forwardButton.accessibilityIdentifier = "TabToolbar.forwardButton"
        searchButton.accessibilityIdentifier = "TabToolbar.searchButton"
        tabsButton.accessibilityIdentifier = "TabToolbar.tabsButton"
        menuButton.accessibilityIdentifier = "TabToolbar.menuButton"
        accessibilityNavigationStyle = .combined
        accessibilityLabel = NSLocalizedString("Navigation Toolbar", comment: "Accessibility label for the navigation toolbar displayed at the bottom of the screen.")
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addButtons(_ buttons: [UIButton]) {
        buttons.forEach { contentView.addArrangedSubview($0) }
    }

    override func draw(_ rect: CGRect) {
        if let context = UIGraphicsGetCurrentContext() {
            drawLine(context, start: .zero, end: CGPoint(x: frame.width, y: 0))
        }
    }

    fileprivate func drawLine(_ context: CGContext, start: CGPoint, end: CGPoint) {
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.05).cgColor)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: start.x, y: start.y))
        context.addLine(to: CGPoint(x: end.x, y: end.y))
        context.strokePath()
    }
}

extension TabToolbar: TabToolbarProtocol {
    func privateModeBadge(visible: Bool) {
        privateModeBadge.show(visible)
    }

    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateReloadStatus(_ isLoading: Bool) {
        helper?.updateReloadStatus(isLoading)
    }

    func updatePageStatus(_ isWebPage: Bool) {
    }

    func updateTabCount(_ count: Int, animated: Bool) {
        tabsButton.updateTabCount(count, animated: animated)
    }
}

extension TabToolbar: Themeable, PrivateModeUI {
    func applyTheme() {
        backgroundColor = UIColor.clear
        helper?.setTheme(forButtons: actionButtons)

        privateModeBadge.badge.tintBackground(color: Theme.browser.background)
        menuButton.setImage(UIImage(named: "nav-menu")?.tinted(withColor: Theme.general.controlTint), for: .normal)
    }

    func applyUIMode(isPrivate: Bool) {
        privateModeBadge(visible: isPrivate)
    }
}
