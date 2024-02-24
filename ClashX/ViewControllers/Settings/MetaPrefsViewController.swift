//
//  MetaPrefsViewController.swift
//  ClashX Meta
//
//  Copyright © 2023 west2online. All rights reserved.
//

import Cocoa

class MetaPrefsViewController: NSViewController {
	// Meta Setting
	@IBOutlet var hideUnselectableButton: NSButton!
	
	@IBAction func hideUnselectable(_ sender: NSButton) {
		var newState = NSControl.StateValue.off
		switch sender.state {
		case .off:
			newState = .mixed
		case .mixed:
			newState = .on
		case .on:
			newState = .off
		default:
			return
		}

		sender.state = newState
		MenuItemFactory.hideUnselectable = newState.rawValue
	}
	
	
	@IBOutlet var autoSleepModeButton: NSButton!
	@IBAction func autoSleepMode(_ sender: NSButton) {
		var newState: NSControl.StateValue = sender.state == .on ? .off : .on
		sender.state = newState
		ConfigManager.autoSleepMode = newState == .on
	}
	
	// Dashboard
	@IBOutlet var useSwiftuiButton: NSButton!
	@IBOutlet var useYacdButton: NSButton!
	@IBOutlet var useXDButton: NSButton!
	
	@IBAction func switchDashboard(_ sender: NSButton) {
		switch sender {
#if SwiftUI_Version
		case useSwiftuiButton:
			DashboardManager.shared.useSwiftUI = sender.state == .on
#endif
		case useYacdButton:
			ConfigManager.useYacdDashboard = sender.state == .on
		case useXDButton:
			ConfigManager.useYacdDashboard = sender.state == .off
		default:
			break
		}
		initDashboardButtons()
	}
	
	// Alpha Core
	@IBOutlet var useAlphaButton: NSButton!
	@IBOutlet var alphaVersionTextField: NSTextField!
	@IBOutlet var updateButton: NSButton!
	@IBOutlet var updateProgressIndicator: NSProgressIndicator!
	@IBOutlet var showAlphaButton: NSButton!
	

	@IBAction func useAlphaMeta(_ sender: NSButton) {
		if UserDefaults.standard.object(forKey: "useAlphaCore") as? Bool == nil {
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Alpha Meta core Warning", comment: "")
			alert.alertStyle = .warning
			alert.addButton(withTitle: NSLocalizedString("Continue", comment: ""))
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
			if alert.runModal() != .alertFirstButtonReturn {
				return
			}
		}

		let use = sender.state == .on
		ConfigManager.useAlphaCore = use
	}
	
	@IBAction func updateAlpha(_ sender: NSButton) {
		sender.isEnabled = false
		updateProgressIndicator.isHidden = false
		updateProgressIndicator.startAnimation(nil)
		AlphaMetaDownloader.alphaAsset().then {
			AlphaMetaDownloader.checkVersion($0)
		}.then {
			AlphaMetaDownloader.downloadCore($0)
		}.then {
			AlphaMetaDownloader.replaceCore($0)
		}.done {
			self.updateAlphaVersion($0)
			let msg = NSLocalizedString("Version: ", comment: "") + $0
			NSUserNotificationCenter.default.post(title: "Clash Meta Core", info: msg)
		}.ensure {
			sender.isEnabled = true
			self.updateProgressIndicator.isHidden = true
			self.updateProgressIndicator.stopAnimation(nil)
		}.catch {
			let error = $0 as? AlphaMetaDownloader.errors
			NSUserNotificationCenter.default.post(title: "Clash Meta Core", info: error?.des() ?? "")
		}
	}
	
	@IBAction func showAlphaInFinder(_ sender: NSButton) {
		guard let u = Paths.alphaCorePath(),
			  FileManager.default.fileExists(atPath: u.path) else { return }
		NSWorkspace.shared.activateFileViewerSelecting([u])
	}
	
	
	override func viewDidLoad() {
        super.viewDidLoad()
		// Meta Setting
		hideUnselectableButton.state = .init(rawValue: MenuItemFactory.hideUnselectable)
		
		// Dashboard
		initDashboardButtons()
		
		// Alpha Core
		useAlphaButton.state = ConfigManager.useAlphaCore ? .on : .off
		updateProgressIndicator.isHidden = true
		setAlphaVersion()
    }
	
	func initDashboardButtons() {
		let useSwiftUI = DashboardManager.shared.useSwiftUI
		let useYacd = ConfigManager.useYacdDashboard
		
		useSwiftuiButton.state = useSwiftUI ? .on : .off
		useYacdButton.state = useYacd ? .on : .off
		useXDButton.state = useYacd ? .off : .on
		
#if SwiftUI_Version
		useSwiftuiButton.isEnabled = true
#else
		useSwiftuiButton.isEnabled = false
#endif
		useYacdButton.isEnabled = !useSwiftUI
		useXDButton.isEnabled = !useSwiftUI
	}
	
	func setAlphaVersion() {
		if let alphaCorePath = Paths.alphaCorePath(),
		   let delegate = NSApplication.shared.delegate as? AppDelegate,
		   let v = delegate.testMetaCore(alphaCorePath.path)?.version {
			updateAlphaVersion(v)
		} else {
			updateAlphaVersion(nil)
		}
	}
	
	func updateAlphaVersion(_ version: String?) {
		let enable = version != nil
		useAlphaButton.isEnabled = enable
		showAlphaButton.isEnabled = enable
		if let v = version {
			alphaVersionTextField.stringValue = v
			updateButton.title = NSLocalizedString("Update Alpha Meta core", comment: "")
		} else {
			alphaVersionTextField.stringValue = "none"
			updateButton.title = NSLocalizedString("Download Meta core", comment: "")
		}
	}
	
}
