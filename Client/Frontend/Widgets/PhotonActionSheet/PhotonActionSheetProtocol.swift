/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage

protocol PhotonActionSheetProtocol {
    var tabManager: TabManager { get }
    var profile: Profile { get }
}

private let log = Logger.browserLogger

extension PhotonActionSheetProtocol {
    typealias PresentableVC = UIViewController & UIPopoverPresentationControllerDelegate
    typealias MenuAction = () -> Void
    typealias IsPrivateTab = Bool
    typealias URLOpenAction = (URL?, IsPrivateTab) -> Void

    func presentSheetWith(title: String? = nil, actions: [[PhotonActionSheetItem]], on viewController: PresentableVC, from view: UIView, closeButtonTitle: String = Strings.CloseButtonTitle, suppressPopover: Bool = false) {
        let style: UIModalPresentationStyle = (UIDevice.current.isPad && !suppressPopover) ? .popover : .overCurrentContext
        let sheet = PhotonActionSheet(title: title, actions: actions, closeButtonTitle: closeButtonTitle, style: style)
        sheet.modalPresentationStyle = style
        sheet.photonTransitionDelegate = PhotonActionSheetAnimator()

        if let popoverVC = sheet.popoverPresentationController, sheet.modalPresentationStyle == .popover {
            popoverVC.delegate = viewController
            popoverVC.sourceView = view
            popoverVC.sourceRect = CGRect(x: view.frame.width/2, y: view.frame.size.height * 0.75, width: 1, height: 1)
            popoverVC.permittedArrowDirections = .up
        }
        viewController.present(sheet, animated: true, completion: nil)
    }

    //Returns a list of actions which is used to build a menu
    //OpenURL is a closure that can open a given URL in some view controller. It is up to the class using the menu to know how to open it
    func getLibraryActions(vcDelegate: PageOptionsVC) -> [PhotonActionSheetItem] {
        guard let tab = self.tabManager.selectedTab else { return [] }

        let openHomePage = PhotonActionSheetItem(title: Strings.AppMenuOpenHomePageTitleString, iconString: "menu-Home") { _ in
            if let homePanelURL = NewTabPage.topSites.url {
                tab.loadRequest(PrivilegedRequest(url: homePanelURL) as URLRequest)
            }
        }

        let openDownloadsItem = self.openDownloadsItem(vcDelegate: vcDelegate)

        return [openHomePage, openDownloadsItem]
    }

    /*
     Returns a list of actions which is used to build the general browser menu
     These items repersent global options that are presented in the menu
     TO DO: These icons should all have the icons and use Strings.swift
     */

    typealias PageOptionsVC = SettingsDelegate & PresentingModalViewControllerDelegate & UIViewController

    func getOtherPanelActions(vcDelegate: PageOptionsVC) -> [PhotonActionSheetItem] {
        return [
            self.openWhatsNewItem(),
            self.openSettingsItem(vcDelegate: vcDelegate),
        ]
    }

    fileprivate func share(fileURL: URL, buttonView: UIView, presentableVC: PresentableVC) {
        let helper = ShareExtensionHelper(url: fileURL, tab: tabManager.selectedTab)
        let controller = helper.createActivityViewController { completed, activityType in
            print("Shared downloaded file: \(completed)")
        }

        if let popoverPresentationController = controller.popoverPresentationController {
            popoverPresentationController.sourceView = buttonView
            popoverPresentationController.sourceRect = buttonView.bounds
            popoverPresentationController.permittedArrowDirections = .up
        }

        presentableVC.present(controller, animated: true, completion: nil)
    }

    func getTabActions(tab: Tab, buttonView: UIView,
                       presentShareMenu: @escaping (URL, Tab, UIView, UIPopoverArrowDirection) -> Void,
                       findInPage:  @escaping () -> Void,
                       presentableVC: PresentableVC,
                       isBookmarked: Bool,
                       isPinned: Bool,
                       isReaderModeEnabled: Bool?,
                       readerModeChanged: ((Bool) -> Void)?,
                       success: @escaping (String) -> Void) -> [[PhotonActionSheetItem]] {
        if tab.url?.isFileURL ?? false {
            let shareFile = PhotonActionSheetItem(title: Strings.AppMenuSharePageTitleString, iconString: "action_share") { action in
                guard let url = tab.url else { return }

                self.share(fileURL: url, buttonView: buttonView, presentableVC: presentableVC)
            }

            return [[shareFile]]
        }

        let defaultUAisDesktop = UserAgent.isDesktop(ua: UserAgent.defaultUserAgent())
        let toggleActionTitle: String
        if defaultUAisDesktop {
            toggleActionTitle = tab.changedUserAgent ? Strings.AppMenuViewDesktopSiteTitleString : Strings.AppMenuViewMobileSiteTitleString
        } else {
            toggleActionTitle = tab.changedUserAgent ? Strings.AppMenuViewMobileSiteTitleString : Strings.AppMenuViewDesktopSiteTitleString
        }

        let toggleDesktopSite = PhotonActionSheetItem(title: toggleActionTitle, iconString: "menu-RequestDesktopSite", isEnabled: tab.changedUserAgent, badgeIconNamed: "menuBadge") { action in
            if let url = tab.url {
                tab.toggleChangeUserAgent()
                Tab.ChangeUserAgent.updateDomainList(forUrl: url, isChangedUA: tab.changedUserAgent, isPrivate: tab.isPrivate)
            }
        }

        let bookmarkPage = PhotonActionSheetItem(title: Strings.AppMenuAddBookmarkTitleString, iconString: "menu-Bookmark") { action in
            guard let url = tab.canonicalURL?.displayURL,
                let bvc = presentableVC as? BrowserViewController else {
                return
            }
            bvc.addBookmark(url: url.absoluteString, title: tab.title, favicon: tab.displayFavicon)
            success(Strings.AppMenuAddBookmarkConfirmMessage)
        }

        let removeBookmark = PhotonActionSheetItem(title: Strings.AppMenuRemoveBookmarkTitleString, iconString: "menu-Bookmark-Remove") { action in
            guard let url = tab.url?.displayURL else { return }

            let absoluteString = url.absoluteString
            self.profile.bookmarks.modelFactory >>== {
                $0.removeByURL(absoluteString).uponQueue(.main) { res in
                    if res.isSuccess {
                        success(Strings.AppMenuRemoveBookmarkConfirmMessage)
                    }
                }
            }
        }

        let pinToTopSites = PhotonActionSheetItem(title: Strings.PinTopsiteActionTitle, iconString: "action_pin") { action in
            guard let url = tab.url?.displayURL, let sql = self.profile.history as? SQLiteHistory else { return }

            sql.getSites(forURLs: [url.absoluteString]).bind { val -> Success in
                guard let site = val.successValue?.asArray().first?.flatMap({ $0 }) else {
                    return succeed()
                }

                return self.profile.history.addPinnedTopSite(site)
            }.uponQueue(.main) { _ in }
        }

        let removeTopSitesPin = PhotonActionSheetItem(title: Strings.RemovePinTopsiteActionTitle, iconString: "action_unpin") { action in
            guard let url = tab.url?.displayURL, let sql = self.profile.history as? SQLiteHistory else { return }

            sql.getSites(forURLs: [url.absoluteString]).bind { val -> Success in
                guard let site = val.successValue?.asArray().first?.flatMap({ $0 }) else {
                    return succeed()
                }

                return self.profile.history.removeFromPinnedTopSites(site)
            }.uponQueue(.main) { _ in }
        }

        let sharePage = PhotonActionSheetItem(title: Strings.AppMenuSharePageTitleString, iconString: "action_share") { action in
            guard let url = tab.canonicalURL?.displayURL else { return }

            if let temporaryDocument = tab.temporaryDocument {
                temporaryDocument.getURL().uponQueue(.main, block: { tempDocURL in
                    // If we successfully got a temp file URL, share it like a downloaded file,
                    // otherwise present the ordinary share menu for the web URL.
                    if tempDocURL.isFileURL {
                        self.share(fileURL: tempDocURL, buttonView: buttonView, presentableVC: presentableVC)
                    } else {
                        presentShareMenu(url, tab, buttonView, .up)
                    }
                })
            } else {
                presentShareMenu(url, tab, buttonView, .up)
            }
        }

        var mainActions = [sharePage]

        // Disable bookmarking if the URL is too long.
        if !tab.urlIsTooLong {
            mainActions.append(isBookmarked ? removeBookmark : bookmarkPage)
        }

        let pinAction = (isPinned ? removeTopSitesPin : pinToTopSites)
        mainActions.append(pinAction)

        let refreshPage = self.refreshPageItem()

        var domainActions = [toggleDesktopSite]

        if let isReaderModeEnabled = isReaderModeEnabled {
            let readerModeAction = PhotonActionSheetItem(title: Strings.AppMenuReaderModeTitleString, iconString: "reader", isEnabled: isReaderModeEnabled, accessory: .Switch, badgeIconNamed: "menuBadge") { (item) in
                tab.toggleChangeReaderMode()
                readerModeChanged?(item.isEnabled)
            }
            domainActions.append(readerModeAction)
        }

        var commonActions = [refreshPage]

        // Disable find in page if document is pdf.
        if tab.mimeType != MIMEType.PDF {
            let findInPageAction = PhotonActionSheetItem(title: Strings.AppMenuFindInPageTitleString, iconString: "menu-FindInPage") { action in
                findInPage()
            }
            commonActions.insert(findInPageAction, at: 0)
        }

        return [mainActions, domainActions, commonActions]
    }

    func fetchBookmarkStatus(for url: String) -> Deferred<Maybe<Bool>> {
        return self.profile.bookmarks.modelFactory.bind {
            guard let factory = $0.successValue else {
                return deferMaybe(false)
            }
            return factory.isBookmarked(url)
        }
    }

    func fetchPinnedTopSiteStatus(for url: String) -> Deferred<Maybe<Bool>> {
        return self.profile.history.isPinnedTopSite(url)
    }

    func getLongPressLocationBarActions(with urlBar: URLBarView) -> [PhotonActionSheetItem] {
        let pasteGoAction = PhotonActionSheetItem(title: Strings.PasteAndGoTitle, iconString: "menu-PasteAndGo") { action in
            if let pasteboardContents = UIPasteboard.general.string {
                urlBar.delegate?.urlBar(urlBar, didSubmitText: pasteboardContents)
            }
        }
        let pasteAction = PhotonActionSheetItem(title: Strings.PasteTitle, iconString: "menu-Paste") { action in
            if let pasteboardContents = UIPasteboard.general.string {
                urlBar.enterOverlayMode(pasteboardContents, pasted: true, search: true)
            }
        }
        let copyAddressAction = PhotonActionSheetItem(title: Strings.CopyAddressTitle, iconString: "menu-Copy-Link") { action in
            if let url = self.tabManager.selectedTab?.canonicalURL?.displayURL ?? urlBar.currentURL {
                UIPasteboard.general.url = url
            }
        }
        if UIPasteboard.general.string != nil {
            return [pasteGoAction, pasteAction, copyAddressAction]
        } else {
            return [copyAddressAction]
        }
    }

    @available(iOS 11.0, *)
    private func menuActionsForNotBlocking() -> [PhotonActionSheetItem] {
        return [PhotonActionSheetItem(title: Strings.SettingsTrackingProtectionSectionName, text: Strings.TPNoBlockingDescription, iconString: "menu-TrackingProtection")]
    }

    @available(iOS 11.0, *)
    private func menuActionsForTrackingProtectionDisabled(for tab: Tab, vcDelegate: PageOptionsVC) -> [[PhotonActionSheetItem]] {
        let moreInfo = PhotonActionSheetItem(title: Strings.TPBlockingMoreInfo)
        return [[moreInfo], [openSettingsItem(vcDelegate: vcDelegate)]]
    }

    @available(iOS 11.0, *)
    private func menuActionsForTrackingProtectionEnabled(for tab: Tab) -> [[PhotonActionSheetItem]] {
        guard let blocker = tab.contentBlocker else {
            return []
        }

        // Menu Actions
        let menuActions = self.menuActions(for: tab)

        // Tracker Info
        let trackerInfoView = PrivacyDashboardView()
        trackerInfoView.blocker = blocker
        let trackerInfo = PhotonActionSheetItem(title: "", customView: trackerInfoView)

        // Whotracks.me link
        guard let baseDomain = blocker.tab?.currentURL()?.baseDomain, let appDel = UIApplication.shared.delegate as? AppDelegate else {
            return [menuActions, [trackerInfo]]
        }

        let whoTracksMeLink = PhotonActionSheetItem(title: Strings.PrivacyDashboard.ViewFullReport + " ›") { action in
            let url = URL(string: "https://whotracks.me/websites/\(baseDomain).html")!
            appDel.browserViewController.homePanel(didSelectURL: url, visitType: VisitType.link)
        }

        if blocker.status == .Disabled {
            return [[whoTracksMeLink]]
        }
        if blocker.stats.total > 0 {
            return [menuActions, [trackerInfo], [whoTracksMeLink]]
        } else {
            return [menuActions, [trackerInfo]]
        }
    }

    @available(iOS 11.0, *)
    private func menuActionsForWhitelistedSite(for tab: Tab) -> [[PhotonActionSheetItem]] {
        return [self.menuActions(for: tab)]
    }

    private func menuActions(for tab: Tab) -> [PhotonActionSheetItem] {
        guard let currentURL = tab.url else {
            return []
        }

        let trackingProtectionEnabled = ContentBlocker.shared.isTrackingWhitelisted(url: currentURL)
        let trackingProtection = PhotonActionSheetItem(
            title: Strings.PrivacyDashboard.Switch.AntiTracking,
            iconString: "menu-TrackingProtection",
            isEnabled: !trackingProtectionEnabled,
            accessory: .Switch
        ) { action in
            ContentBlocker.shared.trackingWhitelist(enable: !trackingProtectionEnabled, url: currentURL) {
                tab.reload()
            }
        }
        let adBlockingEnabled = ContentBlocker.shared.isAdsWhitelisted(url: currentURL)
        let adBlocking = PhotonActionSheetItem(
            title: Strings.PrivacyDashboard.Switch.AdBlock,
            iconString: "menu-AdBlocking",
            isEnabled: !adBlockingEnabled,
            accessory: .Switch
        ) { action in
            ContentBlocker.shared.adsWhitelist(enable: !adBlockingEnabled, url: currentURL) {
                tab.reload()
            }
        }
        return [trackingProtection, adBlocking]
    }

    @available(iOS 11.0, *)
    func getTrackingSubMenu(for tab: Tab, vcDelegate: PageOptionsVC) -> [[PhotonActionSheetItem]] {
        guard let blocker = tab.contentBlocker else {
            return []
        }

        switch blocker.status {
        case .Disabled:
            return menuActionsForTrackingProtectionDisabled(for: tab, vcDelegate: vcDelegate)
        default:
            return menuActionsForTrackingProtectionEnabled(for: tab)
        }
    }

    private func openWhatsNewItem() -> PhotonActionSheetItem {
        let openSettings = PhotonActionSheetItem(title: Strings.AppMenuWhatsNewTitleString, iconString: "menu-whatsNew") { action in
            guard let url = URL(string: Strings.WhatsNewWebsite) else {
                return
            }
            let newTab = self.tabManager.addTab(URLRequest(url: url))
            self.tabManager.selectTab(newTab)
        }
        return openSettings
    }

    private func openSettingsItem(vcDelegate: PageOptionsVC) -> PhotonActionSheetItem {
        let openSettings = PhotonActionSheetItem(title: Strings.AppMenuSettingsTitleString, iconString: "menu-Settings") { action in
            let settingsTableViewController = AppSettingsTableViewController()
            settingsTableViewController.profile = self.profile
            settingsTableViewController.tabManager = self.tabManager
            settingsTableViewController.settingsDelegate = vcDelegate

            let controller = ThemedNavigationController(rootViewController: settingsTableViewController)
            controller.presentingModalViewControllerDelegate = vcDelegate

            // Wait to present VC in an async dispatch queue to prevent a case where dismissal
            // of this popover on iPad seems to block the presentation of the modal VC.
            DispatchQueue.main.async {
                vcDelegate.present(controller, animated: true, completion: nil)
            }
        }
        return openSettings
    }

    private func openDownloadsItem(vcDelegate: PageOptionsVC) -> PhotonActionSheetItem {
        let openDownloads = PhotonActionSheetItem(title: Strings.AppMenuDownloadsTitleString, iconString: "menu-downloads") { action in
            (vcDelegate as? BrowserViewController)?.showDownloads()
        }
        return openDownloads
    }

    private func refreshPageItem() -> PhotonActionSheetItem {
           let refreshPage = PhotonActionSheetItem(title: Strings.AppMenuReloadTitleString, iconString: "nav-refresh") { action in
                self.tabManager.selectedTab?.reload()
           }
           return refreshPage
       }

}
