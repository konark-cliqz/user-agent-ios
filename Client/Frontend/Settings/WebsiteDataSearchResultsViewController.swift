/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit
import Shared
import WebKit

private let SectionHeaderFooterIdentifier = "SectionHeaderFooterIdentifier"

class WebsiteDataSearchResultsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var tableView: UITableView!

    private var filteredSiteRecords = [WKWebsiteDataRecord]()
    var siteRecords = [WKWebsiteDataRecord]()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView = UITableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorColor = Theme.tableView.separator
        tableView.backgroundColor = Theme.tableView.headerBackground
        tableView.isEditing = true
        tableView.register(ThemedTableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(ThemedTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderFooterIdentifier)
        view.addSubview(tableView)

        let footer = ThemedTableSectionHeaderFooterView(frame: CGRect(width: tableView.bounds.width, height: SettingsUX.TableViewHeaderFooterHeight))
        footer.showBottomBorder = false
        tableView.tableFooterView = footer

        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSiteRecords.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        if let record = filteredSiteRecords[safe: indexPath.row] {
            cell.textLabel?.text = record.displayName
        }
        return cell
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == UITableViewCell.EditingStyle.delete, let record = filteredSiteRecords[safe: indexPath.row] else {
            return
        }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, for: [record]) {
            self.filteredSiteRecords.remove(at: indexPath.row)
            self.tableView.reloadData()
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderFooterIdentifier) as? ThemedTableSectionHeaderFooterView
        headerView?.titleLabel.text = Strings.SettingsWebsiteDataTitle
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SettingsUX.TableViewHeaderFooterHeight
    }

    func filterContentForSearchText(_ searchText: String) {
        filteredSiteRecords = siteRecords.filter({ siteRecord in
            return siteRecord.displayName.lowercased().contains(searchText.lowercased())
        })

        tableView.reloadData()
    }
}

extension WebsiteDataSearchResultsViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        filterContentForSearchText(searchController.searchBar.text!)
    }
}
