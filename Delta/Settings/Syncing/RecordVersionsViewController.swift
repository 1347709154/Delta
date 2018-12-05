//
//  RecordVersionsViewController.swift
//  Delta
//
//  Created by Riley Testut on 11/20/18.
//  Copyright © 2018 Riley Testut. All rights reserved.
//

import UIKit

import Roxas
import Harmony

extension RecordVersionsViewController
{
    private enum Section: Int, CaseIterable
    {
        case local
        case remote
        case confirm
    }
    
    private enum Mode
    {
        case restoreVersion
        case resolveConflict
    }
}

private class Version
{
    let version: Harmony.Version
    
    init(_ version: Harmony.Version)
    {
        self.version = version
    }
}

class RecordVersionsViewController: UITableViewController
{
    var record: Record<NSManagedObject>! {
        didSet {
            self.mode = self.record.isConflicted ? .resolveConflict : .restoreVersion
        }
    }
    
    private var mode = Mode.restoreVersion {
        didSet {
            switch self.mode
            {
            case .restoreVersion: self._selectedVersionIndexPath = IndexPath(item: 0, section: Section.local.rawValue)
            case .resolveConflict: self._selectedVersionIndexPath = nil
            }
        }
    }
    
    private var versions: [Version]?
    
    private lazy var dataSource = self.makeDataSource()
    private var remoteVersionsDataSource: RSTArrayTableViewDataSource<Version> {
        let compositeDataSource = self.dataSource.dataSources[1] as! RSTCompositeTableViewDataSource
        
        let dataSource = compositeDataSource.dataSources[1] as! RSTArrayTableViewDataSource<Version>
        return dataSource
    }
    
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .short
        
        return dateFormatter
    }()
    
    private var isSyncingRecord = false
    private var _selectedVersionIndexPath: IndexPath?
    
    private var progressView: UIProgressView!
    
    private var _progressObservation: NSKeyValueObservation?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        self.progressView = UIProgressView(progressViewStyle: .bar)
        self.progressView.translatesAutoresizingMaskIntoConstraints = false
        self.progressView.progress = 0
        
        if let navigationBar = self.navigationController?.navigationBar
        {
            navigationBar.addSubview(self.progressView)
            
            NSLayoutConstraint.activate([self.progressView.leadingAnchor.constraint(equalTo: navigationBar.leadingAnchor),
                                         self.progressView.trailingAnchor.constraint(equalTo: navigationBar.trailingAnchor),
                                         self.progressView.bottomAnchor.constraint(equalTo: navigationBar.bottomAnchor)])
        }
        
        self.tableView.dataSource = self.dataSource
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        self.fetchVersions()
    }
}

private extension RecordVersionsViewController
{
    func makeDataSource() -> RSTCompositeTableViewDataSource<Version>
    {
        func configure(_ cell: UITableViewCell, isSelected: Bool, isEnabled: Bool)
        {
            cell.accessoryType = isSelected ? .checkmark : .none
            
            if isEnabled
            {
                cell.textLabel?.alpha = 1.0
                cell.detailTextLabel?.alpha = 1.0
                cell.selectionStyle = .gray
            }
            else
            {
                cell.textLabel?.alpha = 0.33
                cell.detailTextLabel?.alpha = 0.33
                cell.selectionStyle = .none
            }
        }
        
        let localVersionsDataSource = RSTDynamicTableViewDataSource<Version>()
        localVersionsDataSource.numberOfSectionsHandler = { 1 }
        localVersionsDataSource.numberOfItemsHandler = { _ in self.record.localModificationDate != nil ? 1 : 0 }
        localVersionsDataSource.cellConfigurationHandler = { [weak self] (cell, _, indexPath) in
            guard let `self` = self else { return }
            
            let date = self.record.localModificationDate!
            cell.textLabel?.text = self.dateFormatter.string(from: date)
            cell.detailTextLabel?.text = nil
            
            let isSelected = (indexPath == self._selectedVersionIndexPath)
            configure(cell, isSelected: isSelected, isEnabled: !self.isSyncingRecord)
        }
        
        let remoteVersionsDataSource = RSTArrayTableViewDataSource<Version>(items: [])
        remoteVersionsDataSource.cellConfigurationHandler = { [weak self] (cell, version, indexPath) in
            guard let `self` = self else { return }
            
            cell.textLabel?.text = self.dateFormatter.string(from: version.version.date)
            cell.detailTextLabel?.text = (version.version.identifier == self.record.remoteVersion?.identifier) ? self.record.remoteAuthor : nil
            
            let isSelected = (self._selectedVersionIndexPath?.section == Section.remote.rawValue && self._selectedVersionIndexPath?.row == indexPath.row)
            configure(cell, isSelected: isSelected, isEnabled: !self.isSyncingRecord)
        }
        
        let loadingDataSource = RSTDynamicTableViewDataSource<Version>()
        loadingDataSource.numberOfSectionsHandler = { 1 }
        loadingDataSource.numberOfItemsHandler = { _ in (self.versions == nil) ? 1 : 0 }
        loadingDataSource.cellIdentifierHandler = { _ in "LoadingCell" }
        loadingDataSource.cellConfigurationHandler = { (_, _, _) in }
        
        let remoteVersionsLoadingDataSource = RSTCompositeTableViewDataSource(dataSources: [loadingDataSource, remoteVersionsDataSource])
        remoteVersionsLoadingDataSource.shouldFlattenSections = true
        
        let restoreVersionDataSource = RSTDynamicTableViewDataSource<Version>()
        restoreVersionDataSource.numberOfSectionsHandler = { 1 }
        restoreVersionDataSource.numberOfItemsHandler = { _ in 1}
        restoreVersionDataSource.cellIdentifierHandler = { _ in "ConfirmCell" }
        restoreVersionDataSource.cellConfigurationHandler = { [weak self] (cell, _, indexPath) in
            guard let `self` = self else { return }
            
            switch self.mode
            {
            case .restoreVersion:
                cell.textLabel?.text = NSLocalizedString("Restore Version", comment: "")
                cell.textLabel?.textColor = .deltaPurple
                
                let isEnabled = (self._selectedVersionIndexPath?.section == Section.remote.rawValue && !self.isSyncingRecord)
                configure(cell, isSelected: false, isEnabled: isEnabled)
                
            case .resolveConflict:
                cell.textLabel?.text = NSLocalizedString("Resolve Conflict", comment: "")
                cell.textLabel?.textColor = .red
                
                let isEnabled = (self._selectedVersionIndexPath != nil && !self.isSyncingRecord)
                configure(cell, isSelected: false, isEnabled: isEnabled)
            }
        }
        
        let dataSource = RSTCompositeTableViewDataSource(dataSources: [localVersionsDataSource, remoteVersionsLoadingDataSource, restoreVersionDataSource])
        dataSource.proxy = self
        return dataSource
    }
    
    func fetchVersions()
    {
        SyncManager.shared.syncCoordinator.fetchVersions(for: self.record) { (result) in
            do
            {
                let versions = try result.value().map(Version.init)
                self.versions = versions
                
                DispatchQueue.main.async {
                    let count = self.tableView.numberOfRows(inSection: Section.remote.rawValue)
                    
                    let deletions = (0 ..< count).map { (row) -> RSTCellContentChange in
                        let change = RSTCellContentChange(type: .delete,
                                                          currentIndexPath: IndexPath(row: row, section: 0),
                                                          destinationIndexPath: nil)
                        change.rowAnimation = .fade
                        return change
                    }
                    
                    let inserts = (0 ..< versions.count).map { (row) -> RSTCellContentChange in
                        let change = RSTCellContentChange(type: .insert,
                                                          currentIndexPath: nil,
                                                          destinationIndexPath: IndexPath(row: row, section: 0))
                        change.rowAnimation = .fade
                        return change
                    }
                    
                    let changes = deletions + inserts
                    self.remoteVersionsDataSource.setItems(versions, with: changes)
                }
            }
            catch
            {
                DispatchQueue.main.async {
                    let alertController = UIAlertController(title: NSLocalizedString("Failed to Fetch Record Versions", comment: ""), message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(.ok)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }
    
    func restoreVersion()
    {
        guard !self.isSyncingRecord else { return }
        
        guard let indexPath = self._selectedVersionIndexPath else { return }
        
        func finish(_ result: Result<Record<NSManagedObject>>)
        {
            DispatchQueue.main.async {
                
                CATransaction.begin()
                
                CATransaction.setCompletionBlock {
                    self.isSyncingRecord = false
                    self._progressObservation = nil
                    
                    self.progressView.setHidden(true, animated: true)
                    
                    self.tableView.reloadData()
                    
                    self.navigationItem.rightBarButtonItem?.isIndicatingActivity = false
                    
                    switch result
                    {
                    case .success: self.fetchVersions()
                    case .failure: break
                    }
                }
                
                do
                {
                    let record = try result.value()
                    self.record = record
                    
                    self.progressView.setProgress(1.0, animated: true)
                }
                catch
                {
                    let title: String
                    
                    switch self.mode
                    {
                    case .restoreVersion: title = NSLocalizedString("Failed to Restore Version", comment: "")
                    case .resolveConflict: title = NSLocalizedString("Failed to Resolve Conflict", comment: "")
                    }
                    
                    let alertController = UIAlertController(title: title, message: error.localizedDescription, preferredStyle: .alert)
                    alertController.addAction(.ok)
                    self.present(alertController, animated: true, completion: nil)
                }
                
                CATransaction.commit()
            }
        }
        
        let progress: Progress
        
        switch (self.mode, Section.allCases[indexPath.section])
        {
        case (.restoreVersion, _):
            let version = self.dataSource.item(at: indexPath)
            
            progress = SyncManager.shared.syncCoordinator.restore(self.record, to: version.version) { (result) in
                finish(result)
            }
            
        case (.resolveConflict, .local):
            progress = SyncManager.shared.syncCoordinator.resolveConflictedRecord(self.record, resolution: .local) { (result) in
                finish(result)
            }
            
        case (.resolveConflict, .remote):
            let version = self.dataSource.item(at: indexPath)
            
            progress = SyncManager.shared.syncCoordinator.resolveConflictedRecord(self.record, resolution: .remote(version.version)) { (result) in
                finish(result)
            }
            
        case (.resolveConflict, .confirm): return
        }
        
        self.isSyncingRecord = true
        self.navigationItem.rightBarButtonItem?.isIndicatingActivity = true
        
        self.progressView.progress = 0
        self.progressView.isHidden = false
        
        self._progressObservation = progress.observe(\.fractionCompleted) { [weak progressView] (_, change) in
            DispatchQueue.main.async {
                progressView?.setProgress(Float(progress.fractionCompleted), animated: true)
            }
        }
        
        self.tableView.reloadData()
    }
}

extension RecordVersionsViewController
{
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String?
    {
        switch Section.allCases[section]
        {
        case .local: return NSLocalizedString("Local", comment: "")
        case .remote: return NSLocalizedString("Remote", comment: "")
        case .confirm: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let cell = tableView.cellForRow(at: indexPath), cell.selectionStyle != .none else { return }
        
        switch Section.allCases[indexPath.section]
        {
        case .local, .remote:
            let indexPaths = [indexPath, self._selectedVersionIndexPath, IndexPath(item: 0, section: Section.confirm.rawValue)].compactMap { $0 }
            self._selectedVersionIndexPath = indexPath
            
            tableView.reloadRows(at: indexPaths, with: .none)
            
        case .confirm:
            let message: String
            let actionTitle: String
            
            switch self.mode
            {
            case .restoreVersion:
                message = NSLocalizedString("Restoring a remote version will cause any local changes to be lost.", comment: "")
                actionTitle = NSLocalizedString("Restore Version", comment: "")
                
            case .resolveConflict:
                if self._selectedVersionIndexPath?.section == Section.local.rawValue
                {
                    message = NSLocalizedString("The local version will be uploaded and synced to your other devices.", comment: "")
                }
                else
                {
                    message = NSLocalizedString("Selecting a remote version will cause any local changes to be lost.", comment: "")
                }
                
                actionTitle = NSLocalizedString("Resolve Conflict", comment: "")
            }
            
            let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
            alertController.addAction(.cancel)
            alertController.addAction(UIAlertAction(title: actionTitle, style: .destructive) { (action) in
                self.restoreVersion()
            })
            
            self.present(alertController, animated: true, completion: nil)
        }
    }
}
