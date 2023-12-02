//
//  AppDelegate.swift
//  ClashX
//
//  Created by CYC on 2018/6/10.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Alamofire
import Cocoa
import RxCocoa
import RxSwift
import SwiftyJSON
import Yams
import PromiseKit

let statusItemLengthWithSpeed: CGFloat = 72

private let MetaCoreMd5 = "WOSHIZIDONGSHENGCHENGDEA"

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItem: NSStatusItem!
    @IBOutlet var checkForUpdateMenuItem: NSMenuItem!

    @IBOutlet var statusMenu: NSMenu!
    @IBOutlet var proxySettingMenuItem: NSMenuItem!
    @IBOutlet var autoStartMenuItem: NSMenuItem!

    @IBOutlet var proxyModeGlobalMenuItem: NSMenuItem!
    @IBOutlet var proxyModeDirectMenuItem: NSMenuItem!
    @IBOutlet var proxyModeRuleMenuItem: NSMenuItem!
    @IBOutlet var allowFromLanMenuItem: NSMenuItem!

    @IBOutlet var proxyModeMenuItem: NSMenuItem!
    @IBOutlet var showNetSpeedIndicatorMenuItem: NSMenuItem!
    @IBOutlet var dashboardMenuItem: NSMenuItem!
    @IBOutlet var separatorLineTop: NSMenuItem!
    @IBOutlet var sepatatorLineEndProxySelect: NSMenuItem!
    @IBOutlet var configSeparatorLine: NSMenuItem!
    @IBOutlet var logLevelMenuItem: NSMenuItem!
    @IBOutlet var httpPortMenuItem: NSMenuItem!
    @IBOutlet var socksPortMenuItem: NSMenuItem!
    @IBOutlet var apiPortMenuItem: NSMenuItem!
    @IBOutlet var ipMenuItem: NSMenuItem!
    @IBOutlet var remoteConfigAutoupdateMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandMenuItem: NSMenuItem!
    @IBOutlet var copyExportCommandExternalMenuItem: NSMenuItem!
    @IBOutlet var externalControlSeparator: NSMenuItem!
    @IBOutlet var connectionsMenuItem: NSMenuItem!

    @IBOutlet var tunModeMenuItem: NSMenuItem!

    @IBOutlet var proxyProvidersMenu: NSMenu!
    @IBOutlet var ruleProvidersMenu: NSMenu!
    @IBOutlet var proxyProvidersMenuItem: NSMenuItem!
    @IBOutlet var ruleProvidersMenuItem: NSMenuItem!
    @IBOutlet var snifferMenuItem: NSMenuItem!
    @IBOutlet var flushFakeipCacheMenuItem: NSMenuItem!

    var disposeBag = DisposeBag()
    var statusItemView: StatusItemViewProtocol!
    var isSpeedTesting = false

    var runAfterConfigReload: (() -> Void)?
	
	var helperStatusTimer: Timer?
	var updateGeoTimer: Timer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Logger.log("applicationWillFinishLaunching")
        signal(SIGPIPE, SIG_IGN)
        // crash recorder
        failLaunchProtect()
        NSAppleEventManager.shared()
            .setEventHandler(self,
                             andSelector: #selector(handleURL(event:reply:)),
                             forEventClass: AEEventClass(kInternetEventClass),
                             andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("———————————————applicationDidFinishLaunching———————————————")
        Logger.log("———————————————————————————————————————————————————————————")
        Logger.log("Appversion: \(AppVersionUtil.currentVersion) \(AppVersionUtil.currentBuild)")
        ProcessInfo.processInfo.disableSuddenTermination()
        // setup menu item first
        statusItem = NSStatusBar.system.statusItem(withLength: statusItemLengthWithSpeed)
        statusItemView = StatusItemView.create(statusItem: statusItem)
        statusItemView.updateSize(width: statusItemLengthWithSpeed)
        statusMenu.delegate = self
        setupStatusMenuItemData()
        DispatchQueue.main.async {
            self.postFinishLaunching()
        }
    }

    func postFinishLaunching() {
        Logger.log("postFinishLaunching")
        defer {
            statusItem.menu = statusMenu
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                self.checkMenuIconVisable()
            }
        }
        if #unavailable(macOS 10.15) {
            // dashboard is not support in macOS 10.15 below
            self.dashboardMenuItem.isHidden = true
            self.connectionsMenuItem.isHidden = true
        }
        AppVersionUtil.showUpgradeAlert()
        ICloudManager.shared.setup()

        if WebPortalManager.hasWebProtal {
            WebPortalManager.shared.addWebProtalMenuItem(&statusMenu)
        }
        AutoUpgardeManager.shared.setup()
        AutoUpgardeManager.shared.setupCheckForUpdatesMenuItem(checkForUpdateMenuItem)
        // install proxy helper
        _ = ClashResourceManager.check()
        PrivilegedHelperManager.shared.checkInstall()
        ConfigFileManager.copySampleConfigIfNeed()

        // claer not existed selected model
        removeUnExistProxyGroups()
        setupData()
        runAfterConfigReload = { [weak self] in
            self?.selectAllowLanWithMenory()
        }

        updateLoggingLevel()

        // start watch config file change
        ConfigManager.watchCurrentConfigFile()

        RemoteConfigManager.shared.autoUpdateCheck()

        setupNetworkNotifier()
        registCrashLogger()
        KeyboardShortCutManager.setup()
        RemoteControlManager.setupMenuItem(separator: externalControlSeparator)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return TerminalConfirmAction.run()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        UserDefaults.standard.set(0, forKey: "launch_fail_times")
        Logger.log("ClashX will terminate")
        if NetworkChangeNotifier.isCurrentSystemSetToClash(looser: true) ||
            NetworkChangeNotifier.hasInterfaceProxySetToClash() {
            Logger.log("Need Reset Proxy Setting again", level: .error)
            SystemProxyManager.shared.disableProxy()
        }
    }

    func checkMenuIconVisable() {
        guard let button = statusItem.button else { assertionFailure(); return }
        guard let window = button.window else { assertionFailure(); return }
        let buttonRect = button.convert(button.bounds, to: nil)
        let onScreenRect = window.convertToScreen(buttonRect)
        var leftScreenX: CGFloat = 0
        for screen in NSScreen.screens where screen.frame.origin.x < leftScreenX {
            leftScreenX = screen.frame.origin.x
        }
        let isMenuIconHidden = onScreenRect.midX < leftScreenX

        var isCoverdByNotch = false
        if #available(macOS 12, *), NSScreen.screens.count == 1, let screen = NSScreen.screens.first, let leftArea = screen.auxiliaryTopLeftArea, let rightArea = screen.auxiliaryTopRightArea {
            if onScreenRect.minX > leftArea.maxX, onScreenRect.maxX < rightArea.minX {
                isCoverdByNotch = true
            }
        }

        Logger.log("checkMenuIconVisable: \(onScreenRect) \(leftScreenX), hidden: \(isMenuIconHidden), coverd by notch:\(isCoverdByNotch)")

        if isMenuIconHidden || isCoverdByNotch, !Settings.disableMenubarNotice {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("The status icon is coverd or hide by other app.", comment: "")
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("Never show again", comment: ""))
            if alert.runModal() == .alertSecondButtonReturn {
                Settings.disableMenubarNotice = true
            }
        }
    }

    func setupStatusMenuItemData() {
        ConfigManager.shared
            .showNetSpeedIndicatorObservable
            .bind { [weak self] show in
                guard let self = self else { return }
                self.showNetSpeedIndicatorMenuItem.state = (show ?? true) ? .on : .off
                let statusItemLength: CGFloat = (show ?? true) ? statusItemLengthWithSpeed : 25
                self.statusItem.length = statusItemLength
                self.statusItemView.updateSize(width: statusItemLength)
                self.statusItemView.showSpeedContainer(show: show ?? true)
            }.disposed(by: disposeBag)

        statusItemView.updateViewStatus(enableProxy: ConfigManager.shared.proxyPortAutoSet)

    }
	
    func setupData() {
        SSIDSuspendTool.shared.setup()
        ConfigManager.shared
            .showNetSpeedIndicatorObservable.skip(1)
            .bind {
                _ in
                ApiRequest.shared.resetTrafficStreamApi()
            }.disposed(by: disposeBag)

        Observable
            .merge([ConfigManager.shared.proxyPortAutoSetObservable,
                    ConfigManager.shared.isProxySetByOtherVariable.asObservable(),
                    ConfigManager.shared.proxyShouldPaused.asObservable()])
            .observe(on: MainScheduler.instance)
            .map { _ -> NSControl.StateValue in
                if (ConfigManager.shared.isProxySetByOtherVariable.value || ConfigManager.shared.proxyShouldPaused.value) && ConfigManager.shared.proxyPortAutoSet {
                    return .mixed
                }
                return ConfigManager.shared.proxyPortAutoSet ? .on : .off
            }.distinctUntilChanged()
            .bind { [weak self] status in
                guard let self = self else { return }
                self.proxySettingMenuItem.state = status
            }.disposed(by: disposeBag)

        Observable
            .merge([ConfigManager.shared.proxyPortAutoSetObservable,
                    ConfigManager.shared.isTunModeVariable.asObservable(),
                    ConfigManager.shared.isProxySetByOtherVariable.asObservable()])
            .map { _ -> Bool in
                var status = NSControl.StateValue.mixed
                if ConfigManager.shared.isProxySetByOtherVariable.value && ConfigManager.shared.proxyPortAutoSet {

                } else {
                    status = ConfigManager.shared.proxyPortAutoSet ? .on : .off
                }
                return status == .on || ConfigManager.shared.isTunModeVariable.value
            }.distinctUntilChanged()
            .bind { [weak self] enable in
                guard let self = self else { return }
                self.statusItemView.updateViewStatus(enableProxy: enable)
            }.disposed(by: disposeBag)

        let configObservable = ConfigManager.shared
            .currentConfigVariable
            .asObservable()
        Observable.zip(configObservable, configObservable.skip(1))
            .filter { _, new in return new != nil }
            .observe(on: MainScheduler.instance)
            .bind { [weak self] old, config in
                guard let self = self, let config = config else { return }
                self.proxyModeDirectMenuItem.state = .off
                self.proxyModeGlobalMenuItem.state = .off
                self.proxyModeRuleMenuItem.state = .off

                switch config.mode {
                case .direct: self.proxyModeDirectMenuItem.state = .on
                case .global: self.proxyModeGlobalMenuItem.state = .on
                case .rule: self.proxyModeRuleMenuItem.state = .on
                }
                self.allowFromLanMenuItem.state = config.allowLan ? .on : .off

                self.proxyModeMenuItem.title = "\(NSLocalizedString("Proxy Mode", comment: "")) (\(config.mode.name))"

                if old?.usedHttpPort != config.usedHttpPort || old?.usedSocksPort != config.usedSocksPort {
                    Logger.log("port config updated,new: \(config.usedHttpPort),\(config.usedSocksPort)")
                    if ConfigManager.shared.proxyPortAutoSet {
                        SystemProxyManager.shared.enableProxy(port: config.usedHttpPort, socksPort: config.usedSocksPort)
                    }
                }

                self.httpPortMenuItem.title = "Http Port: \(config.usedHttpPort)"
                self.socksPortMenuItem.title = "Socks Port: \(config.usedSocksPort)"
                self.apiPortMenuItem.title = "Api Port: \(ConfigManager.shared.apiPort)"
                self.ipMenuItem.title = "IP: \(NetworkChangeNotifier.getPrimaryIPAddress() ?? "")"

                if RemoteControlManager.selectConfig == nil {
                    ClashStatusTool.checkPortConfig(cfg: config)
                }

                self.snifferMenuItem.state = config.sniffing ? .on : .off
                self.tunModeMenuItem.state = config.tun.enable ? .on : .off
                ConfigManager.shared.isTunModeVariable.accept(config.tun.enable)
            }.disposed(by: disposeBag)

        // start proxy
		PrivilegedHelperManager.shared.isHelperReady
			.filter({$0})
			.take(1)
			.observe(on: MainScheduler.instance)
			.bind(onNext: { _ in
				Logger.log("HelperReady")
				self.initMetaCore()
				self.startProxy()
			}).disposed(by: disposeBag)
		
		helperStatusTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { timer in
			timer.fireDate = .init(timeIntervalSinceNow: 3600)
			
			PrivilegedHelperManager.shared.helper {
				Logger.log("Check helper status Error, will try again")
				timer.fireDate = .init(timeIntervalSinceNow: 0.3)
			}?.getVersion {
				Logger.log("Check helper status success \($0 ?? "")")
				timer.invalidate()
				PrivilegedHelperManager.shared.isHelperReady.accept(true)
			}
		}
		
		if !PrivilegedHelperManager.shared.isHelperCheckFinished.value {
			proxySettingMenuItem.target = nil
			tunModeMenuItem.target = nil
			PrivilegedHelperManager.shared.isHelperCheckFinished
				.filter({$0})
				.take(1)
				.observe(on: MainScheduler.instance)
				.subscribe { [weak self] _ in
					guard let self = self else { return }
					self.proxySettingMenuItem.target = self
					self.tunModeMenuItem.target = self
					
					self.helperStatusTimer?.fire()
				}.disposed(by: disposeBag)
		} else {
			helperStatusTimer?.fire()
		}
		
		Logger.log("Fire helperStatusTimer")

		
        if !PrivilegedHelperManager.shared.isHelperCheckFinished.value &&
            ConfigManager.shared.proxyPortAutoSet {
            PrivilegedHelperManager.shared.isHelperCheckFinished
                .filter { $0 }
                .take(1)
                .take(while: { _ in ConfigManager.shared.proxyPortAutoSet })
                .observe(on: MainScheduler.instance)
                .bind(onNext: { _ in
                    SystemProxyManager.shared.enableProxy()
                }).disposed(by: disposeBag)
        } else if ConfigManager.shared.proxyPortAutoSet {
            SystemProxyManager.shared.enableProxy()
        }

        LaunchAtLogin.shared
            .isEnableVirable
            .asObservable()
            .subscribe(onNext: { [weak self] enable in
                guard let self = self else { return }
                self.autoStartMenuItem.state = enable ? .on : .off
            }).disposed(by: disposeBag)

        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off

        if !PrivilegedHelperManager.shared.isHelperCheckFinished.value {
            proxySettingMenuItem.target = nil
            PrivilegedHelperManager.shared.isHelperCheckFinished
                .filter { $0 }
                .take(1)
                .observe(on: MainScheduler.instance)
                .subscribe { [weak self] _ in
                    guard let self = self else { return }
                    self.proxySettingMenuItem.target = self
                }.disposed(by: disposeBag)
        }
    }

    func setupNetworkNotifier() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            NetworkChangeNotifier.start()
        }

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusDidChange)
            .observe(on: MainScheduler.instance)
            .delay(.milliseconds(200), scheduler: MainScheduler.instance)
            .bind { _ in
                guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }
                let proxySetted = NetworkChangeNotifier.isCurrentSystemSetToClash()
                ConfigManager.shared.isProxySetByOtherVariable.accept(!proxySetted)
                if !proxySetted && ConfigManager.shared.proxyPortAutoSet {
                    let proxiesSetting = NetworkChangeNotifier.getRawProxySetting()
                    Logger.log("Proxy changed by other process!, current:\(proxiesSetting), is Interface Set: \(NetworkChangeNotifier.hasInterfaceProxySetToClash())", level: .warning)
                }
            }.disposed(by: disposeBag)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(resetProxySettingOnWakeupFromSleep),
            name: NSWorkspace.didWakeNotification, object: nil
        )

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusIPUpdate).map { _ in
                NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false)
            }
            .startWith(NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false))
            .distinctUntilChanged()
            .skip(1)
            .filter { $0 != nil }
            .observe(on: MainScheduler.instance)
            .debounce(.seconds(5), scheduler: MainScheduler.instance).bind { [weak self] _ in
                self?.healthCheckOnNetworkChange()
            }.disposed(by: disposeBag)

        ConfigManager.shared
            .isProxySetByOtherVariable
            .asObservable()
            .filter { _ in ConfigManager.shared.proxyPortAutoSet }
            .distinctUntilChanged()
            .filter { $0 }
            .filter { _ in !ConfigManager.shared.proxyShouldPaused.value }
            .bind { _ in
                let rawProxy = NetworkChangeNotifier.getRawProxySetting()
                Logger.log("proxy changed to no clashX setting: \(rawProxy)", level: .warning)
                NSUserNotificationCenter.default.postProxyChangeByOtherAppNotice()
            }.disposed(by: disposeBag)

        NotificationCenter
            .default
            .rx
            .notification(.systemNetworkStatusIPUpdate).map { _ in
                NetworkChangeNotifier.getPrimaryIPAddress(allowIPV6: false)
            }.bind { [weak self] _ in
                if RemoteControlManager.selectConfig != nil {
                    self?.resetStreamApi()
                }
            }.disposed(by: disposeBag)
    }

    func updateProxyList(withMenus menus: [NSMenuItem]) {
        let startIndex = statusMenu.items.firstIndex(of: separatorLineTop)! + 1
        let endIndex = statusMenu.items.firstIndex(of: sepatatorLineEndProxySelect)!
        sepatatorLineEndProxySelect.isHidden = menus.isEmpty
        for _ in 0 ..< endIndex - startIndex {
            statusMenu.removeItem(at: startIndex)
        }
        for each in menus {
            statusMenu.insertItem(each, at: startIndex)
        }
    }

    func updateConfigFiles() {
        guard let menu = configSeparatorLine.menu else { return }
        MenuItemFactory.generateSwitchConfigMenuItems {
            items in
            let lineIndex = menu.items.firstIndex(of: self.configSeparatorLine)!
            for _ in 0 ..< lineIndex {
                menu.removeItem(at: 0)
            }
            for item in items.reversed() {
                menu.insertItem(item, at: 0)
            }
        }
    }

    func updateLoggingLevel() {
        ApiRequest.updateLogLevel(level: ConfigManager.selectLoggingApiLevel)
        for item in logLevelMenuItem.submenu?.items ?? [] {
            item.state = item.title.lowercased() == ConfigManager.selectLoggingApiLevel.rawValue ? .on : .off
        }
        NotificationCenter.default.post(name: .reloadDashboard, object: nil)
    }

    func initMetaCore() {
        Logger.log("initClashCore")

        let corePath: (String?, String?) = {
			guard let alphaCorePath = Paths.alphaCorePath(),
				  let corePath = Paths.defaultCorePath() else {
				return (nil, "Paths error")
			}

			// alpha core
			if let _ = testMetaCore(alphaCorePath.path) {
				if ConfigManager.useAlphaCore {
					return (alphaCorePath.path, nil)
				}
			}

			let fm = FileManager.default

			// unzip internal core
			if !fm.fileExists(atPath: corePath.path) {
				if let msg = unzipMetaCore() {
					return (nil, msg)
				}
			} else if !validateDefaultCore() {
				try? fm.removeItem(at: corePath)
				if let msg = unzipMetaCore() {
					return (nil, msg)
				}
			}

			if let msg = testMetaCore(corePath.path) {
				Logger.log("version: \(msg.version)")
			}

			// validate md5
			if validateDefaultCore() {
				return (corePath.path, nil)
			} else {
				Logger.log("Failure to verify the internal Meta Core.")
				Logger.log(corePath.path)
				return (nil, "Failure to verify the internal Meta Core.\nDo NOT replace core file in the resources folder.")
			}
        }()

		if let path = corePath.0 {
			RemoteConfigManager.shared.verifyConfigTask.setLaunchPath(path)
			PrivilegedHelperManager.shared.helper()?.initMetaCore(withPath: path)
			Logger.log("initClashCore finish")
		} else {
			let msg = corePath.1 ?? "Load internal Meta Core failed."

			let alert = NSAlert()
			alert.messageText = msg
			alert.alertStyle = .warning
			alert.addButton(withTitle: NSLocalizedString("Quit", comment: ""))
			alert.runModal()

			DispatchQueue.main.async {
				NSApplication.shared.terminate(nil)
			}
		}
    }

    func unzipMetaCore() -> String? {
		guard let corePath = Paths.defaultCorePath(),
			  let gzPath = Paths.defaultCoreGzPath() else { return "Paths error" }
		let fm = FileManager.default
        do {
            let data = try Data(contentsOf: .init(fileURLWithPath: gzPath)).gunzipped()

			if !fm.fileExists(atPath: corePath.deletingLastPathComponent().path) {
				try fm.createDirectory(at: corePath.deletingLastPathComponent(), withIntermediateDirectories: true)
			}

            try data.write(to: corePath)
            return nil
        } catch let error {
			let msg = "Unzip Meta failed: \(error)"
            Logger.log(msg, level: .error)
			return msg
        }
    }

    func testMetaCore(_ path: String) -> (version: String, date: Date?)? {
		guard chmodX(path) else { return nil }

        let proc = Process()
        proc.executableURL = .init(fileURLWithPath: path)
        proc.arguments = ["-v"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        do {
            try proc.run()
        } catch let error {
            Logger.log(error.localizedDescription)
            return nil
        }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard proc.terminationStatus == 0,
              let out = String(data: data, encoding: .utf8) else {
            return nil
        }

		Logger.log("test core path: \(path)")
		Logger.log("-v out: \(out)")
		
		let outs = out
			.split(separator: "\n")
			.first {
				$0.starts(with: "Clash Meta") || $0.starts(with: "Mihomo Meta")
			}?.split(separator: " ")
			.map(String.init)

        guard let outs,
			  outs.count == 13,
              (outs[0] == "Clash" || outs[0] == "Mihomo"),
              outs[1] == "Meta",
              outs[3] == "darwin" else {
            return nil
        }

        let version = outs[2]

		let dateString = [outs[7], outs[8], outs[9], outs[10], outs[12]].joined(separator: "-")
		let f = DateFormatter()
		f.dateFormat = "E-MMM-d-HH:mm:ss-yyyy"
		f.timeZone = .init(abbreviation: outs[11])
		let date = f.date(from: dateString)

		return (version: version, date: date)
    }

    func validateDefaultCore() -> Bool {
		guard let path = Paths.defaultCorePath()?.path,
			  chmodX(path) else { return false }

        #if DEBUG
            return true
        #endif
        let proc = Process()
        proc.executableURL = .init(fileURLWithPath: "/sbin/md5")
		proc.arguments = ["-q", path]
        let pipe = Pipe()
        proc.standardOutput = pipe

        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let out = String(data: data, encoding: .utf8) else {
            return false
        }

        let md5 = out.replacingOccurrences(of: "\n", with: "")
        return md5 == MetaCoreMd5
    }

    func chmodX(_ path: String) -> Bool {
        let proc = Process()
        proc.executableURL = .init(fileURLWithPath: "/bin/chmod")
        proc.arguments = ["+x", path]
        do {
            try proc.run()
        } catch let error {
            Logger.log("chmod +x failed. \(error.localizedDescription)")
            return false
        }
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    }

    func syncConfig(completeHandler: (() -> Void)? = nil) {
        ApiRequest.requestConfig { config in
            ConfigManager.shared.currentConfig = config
            completeHandler?()
        }
    }

    func syncConfigWithTun(_ isInit: Bool = false,
                           _ completeHandler: (() -> Void)? = nil) {
        syncConfig {
            defer {
                completeHandler?()
            }

            guard let config = ConfigManager.shared.currentConfig else { return }

            let enable = config.tun.enable

            if isInit, !enable {
                Logger.log("tun didn't set")
                return
            }

            PrivilegedHelperManager.shared.helper()?.updateTun(with: enable)
            Logger.log("tun state updated, new: \(enable)")
        }
    }

    func resetStreamApi() {
        ApiRequest.shared.delegate = self
        ApiRequest.shared.resetStreamApis()
    }

    func updateConfig(configName: String? = nil, showNotification: Bool = true, completeHandler: ((ErrorString?) -> Void)? = nil) {
        startProxy()
        guard ConfigManager.shared.isRunning else { return }

        let config = configName ?? ConfigManager.selectConfigName

        ClashProxy.cleanCache()

        ApiRequest.requestConfigUpdate(configName: config) {
            [weak self] err in
            guard let self = self else { return }

            defer {
                completeHandler?(err)
            }

            if let err {
                UpdateConfigAction.showError(text: err, configName: config)
            } else {
                self.syncConfigWithTun()
                self.resetStreamApi()
                self.runAfterConfigReload?()
                self.runAfterConfigReload = nil
                if showNotification {
                    NSUserNotificationCenter.default
                        .post(title: NSLocalizedString("Reload Config Succeed", comment: ""),
                              info: NSLocalizedString("Success", comment: ""))
                }

                if let newConfigName = configName {
                    ConfigManager.selectConfigName = newConfigName
                }
                self.selectProxyGroupWithMemory()
                self.selectOutBoundModeWithMenory()
                MenuItemFactory.recreateProxyMenuItems()
                NotificationCenter.default.post(name: .reloadDashboard, object: nil)
            }
        }
    }


    @objc func resetProxySettingOnWakeupFromSleep() {
        guard !ConfigManager.shared.isProxySetByOtherVariable.value,
              ConfigManager.shared.proxyPortAutoSet else { return }
        guard NetworkChangeNotifier.getPrimaryInterface() != nil else { return }
        if !NetworkChangeNotifier.isCurrentSystemSetToClash() {
            let rawProxy = NetworkChangeNotifier.getRawProxySetting()
            Logger.log("Resting proxy setting, current:\(rawProxy)", level: .warning)
            SystemProxyManager.shared.disableProxy()
            SystemProxyManager.shared.enableProxy()
        }

        if RemoteControlManager.selectConfig != nil {
            resetStreamApi()
        }
    }

    @objc func healthCheckOnNetworkChange() {
        ApiRequest.getMergedProxyData {
            proxyResp in
            guard let proxyResp = proxyResp else { return }

            var providers = Set<ClashProxyName>()

            let groups = proxyResp.proxyGroups.filter(\.type.isAutoGroup)
            for group in groups {
                group.all?.compactMap {
                    proxyResp.proxiesMap[$0]?.enclosingProvider?.name
                }.forEach {
                    providers.insert($0)
                }
            }

            for group in groups {
                Logger.log("Start auto health check for group \(group.name)")
                ApiRequest.healthCheck(proxy: group.name)
            }

            for provider in providers {
                Logger.log("Start auto health check for provider \(provider)")
                ApiRequest.healthCheck(proxy: provider)
            }
        }
    }
}

// MARK: Meta Core

extension AppDelegate {

    enum StartMetaError: Error {
        case configMissing
        case remoteConfigMissing
        case startMetaFailed(String)
        case helperNotFound
        case pushConfigFailed(String)
    }

    struct StartProxyResp: Codable {
        let externalController: String
        let secret: String
        let log: String?
    }

    func startProxy() {
        if ConfigManager.shared.isRunning { return }

        Logger.log("Trying start meta core")

        prepareConfigFile().then {
            self.generateInitConfig()
        }.then {
            self.startMeta($0)
        }.get { res in
            if let log = res.log {
                Logger.log("""
\n########  Clash Meta Start Log  #########
\(log)
########  END  #########
""", level: .info)
            }

            let port = res.externalController.components(separatedBy: ":").last ?? "9090"
            ConfigManager.shared.apiPort = port
            ConfigManager.shared.apiSecret = res.secret
            ConfigManager.shared.isRunning = true
            self.proxyModeMenuItem.isEnabled = true
            self.dashboardMenuItem.isEnabled = true
        }.then { _ in
            self.pushInitConfig()
        }.done {
            Logger.log("Init config file success.")
			
			self.showUpdateNotification("ClashX_Meta_1.3.0_UpdateTips", info: "Config Floder migrated from\n~/.config/clash to\n~/.config/clash.meta")
			
			
        }.catch { error in
            ConfigManager.shared.isRunning = false
            self.proxyModeMenuItem.isEnabled = false
            Logger.log("\(error)", level: .error)

            let unc = NSUserNotificationCenter.default

            switch error {
            case StartMetaError.configMissing:
                unc.postConfigErrorNotice(msg: "Can't find config.")
            case StartMetaError.remoteConfigMissing:
                unc.postConfigErrorNotice(msg: "Can't find remote config.")
            case StartMetaError.helperNotFound:
                unc.postMetaErrorNotice(msg: "Can't connect to helper.")
            case StartMetaError.startMetaFailed(let s):
                unc.postMetaErrorNotice(msg: s)
            case StartMetaError.pushConfigFailed(let s):
                unc.postConfigErrorNotice(msg: s)
            default:
                unc.postMetaErrorNotice(msg: "Unknown Error.")
            }
        }
    }

    func prepareConfigFile() -> Promise<()> {
        .init { resolver in
            let configName = ConfigManager.selectConfigName
            ApiRequest.findConfigPath(configName: configName) { path in
                guard let path = path else {
                    resolver.reject(StartMetaError.configMissing)
                    return
                }
                if !FileManager.default.fileExists(atPath: path) {
                    Logger.log("\(configName) not exists")
                    if let config = RemoteConfigManager.shared.configs.first(where: { $0.name == configName }) {
                        Logger.log("Try to download remote config \(configName)")
                        RemoteConfigManager.updateConfig(config: config) {
                            if let error = $0 {
                                Logger.log("Download remote config failed, \(error)")
                                resolver.reject(StartMetaError.remoteConfigMissing)
                            } else {
                                Logger.log("Download remote config success")
                                resolver.fulfill_()
                            }
                        }
                    } else {
                        if configName != "config" {
                            ConfigManager.selectConfigName = "config"
                        }

                        Logger.log("Try to copy default config")
                        ICloudManager.shared.setup()
                        ConfigFileManager.copySampleConfigIfNeed()
                        resolver.fulfill_()
                    }
                } else {
                    resolver.fulfill_()
                }
            }
        }
    }

    func generateInitConfig() -> Promise<ClashMetaConfig.Config> {
        Promise { resolver in
            ClashMetaConfig.generateInitConfig {
                var config = $0
                PrivilegedHelperManager.shared.helper {
//                    resolver.reject(StartMetaError.helperNotFound)
					Logger.log("helperNotFound, getUsedPorts failed", level: .error)
					resolver.fulfill(config)
                }?.getUsedPorts {
                    config.updatePorts($0 ?? "")
                    resolver.fulfill(config)
                }
            }
        }
    }

    func startMeta(_ config: ClashMetaConfig.Config) -> Promise<StartProxyResp> {
        .init { resolver in
            PrivilegedHelperManager.shared.helper {
				Logger.log("helperNotFound, startMeta failed", level: .error)
                resolver.reject(StartMetaError.helperNotFound)
            }?.startMeta(withConfPath: kConfigFolderPath,
                         confFilePath: config.path) {
                if let string = $0 {
                    guard let jsonData = string.data(using: .utf8),
                          let res = try? JSONDecoder().decode(StartProxyResp.self, from: jsonData) else {
                        resolver.reject(StartMetaError.startMetaFailed(string))
                        return
                    }

                    resolver.fulfill(res)
                } else {
                    resolver.reject(StartMetaError.startMetaFailed($0 ?? "unknown error"))
                }
            }
        }
    }

    func pushInitConfig() -> Promise<()> {
        .init { resolver in
            ClashProxy.cleanCache()
            let configName = ConfigManager.selectConfigName
            Logger.log("Push init config file: \(configName)")
            ApiRequest.requestConfigUpdate(configName: configName) { err in
                if let error = err {
                    resolver.reject(StartMetaError.pushConfigFailed(error))
                } else {
                    self.syncConfigWithTun(true)
                    self.resetStreamApi()
                    self.runAfterConfigReload?()
                    self.runAfterConfigReload = nil
                    self.selectProxyGroupWithMemory()
                    MenuItemFactory.recreateProxyMenuItems()
                    NotificationCenter.default.post(name: .reloadDashboard, object: nil)
                    resolver.fulfill_()
                }
            }
        }
    }
}

// MARK: Main actions

extension AppDelegate {
    @IBAction func actionDashboard(_ sender: NSMenuItem?) {
		DashboardManager.shared.show(sender)
    }

    @IBAction func actionAllowFromLan(_ sender: NSMenuItem) {
        ApiRequest.updateAllowLan(allow: !ConfigManager.allowConnectFromLan) {
            [weak self] in
            guard let self = self else { return }
            self.syncConfig()
            ConfigManager.allowConnectFromLan = !ConfigManager.allowConnectFromLan
        }
    }

    @IBAction func actionStartAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.shared.isEnabled = !LaunchAtLogin.shared.isEnabled
    }

    @IBAction func actionSwitchProxyMode(_ sender: NSMenuItem) {
        let mode: ClashProxyMode
        switch sender {
        case proxyModeGlobalMenuItem:
            mode = .global
        case proxyModeDirectMenuItem:
            mode = .direct
        case proxyModeRuleMenuItem:
            mode = .rule
        default:
            return
        }
        switchProxyMode(mode: mode)
    }

    func switchProxyMode(mode: ClashProxyMode) {
        let config = ConfigManager.shared.currentConfig?.copy()
        config?.mode = mode
        ApiRequest.updateOutBoundMode(mode: mode) { _ in
            ConfigManager.shared.currentConfig = config
            ConfigManager.selectOutBoundMode = mode
            MenuItemFactory.recreateProxyMenuItems()
        }
    }

    @IBAction func actionShowNetSpeedIndicator(_ sender: NSMenuItem) {
        ConfigManager.shared.showNetSpeedIndicator = !(sender.state == .on)
    }

    @IBAction func actionSetSystemProxy(_ sender: Any?) {
        var canSaveProxy = true
        if ConfigManager.shared.proxyPortAutoSet && ConfigManager.shared.proxyShouldPaused.value {
            ConfigManager.shared.proxyPortAutoSet = false
        } else if ConfigManager.shared.isProxySetByOtherVariable.value {
            // should reset proxy to clashx
            ConfigManager.shared.isProxySetByOtherVariable.accept(false)
            ConfigManager.shared.proxyPortAutoSet = true
            // clear then reset.
            canSaveProxy = false
            SystemProxyManager.shared.disableProxy(port: 0, socksPort: 0, forceDisable: true)
        } else {
            ConfigManager.shared.proxyPortAutoSet = !ConfigManager.shared.proxyPortAutoSet
        }

        if ConfigManager.shared.proxyPortAutoSet {
            if canSaveProxy {
                SystemProxyManager.shared.saveProxy()
            }
            SystemProxyManager.shared.enableProxy()
        } else {
            SystemProxyManager.shared.disableProxy()
        }
    }

    @IBAction func actionCopyExportCommand(_ sender: NSMenuItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let port = ConfigManager.shared.currentConfig?.usedHttpPort ?? 0
        let socksport = ConfigManager.shared.currentConfig?.usedSocksPort ?? 0
        let localhost = "127.0.0.1"
        let isLocalhostCopy = sender == copyExportCommandMenuItem
        let ip = isLocalhostCopy ? localhost :
            NetworkChangeNotifier.getPrimaryIPAddress() ?? localhost
        pasteboard.setString("export https_proxy=http://\(ip):\(port) http_proxy=http://\(ip):\(port) all_proxy=socks5://\(ip):\(socksport)", forType: .string)
    }

    @IBAction func actionSpeedTest(_ sender: Any) {
        if isSpeedTesting {
            NSUserNotificationCenter.default.postSpeedTestingNotice()
            return
        }
        NSUserNotificationCenter.default.postSpeedTestBeginNotice()

        isSpeedTesting = true

        ApiRequest.getMergedProxyData { [weak self] resp in
            let group = DispatchGroup()

            for (name, _) in resp?.enclosingProviderResp?.providers ?? [:] {
                group.enter()
                ApiRequest.healthCheck(proxy: name) {
                    group.leave()
                }
            }

            for p in resp?.proxiesMap["GLOBAL"]?.all ?? [] {
                group.enter()
                ApiRequest.getProxyDelay(proxyName: p) { _ in
                    group.leave()
                }
            }
            group.notify(queue: DispatchQueue.main) {
                NSUserNotificationCenter.default.postSpeedTestFinishNotice()
                self?.isSpeedTesting = false
            }
        }
    }

    @IBAction func actionUpdateExternalResource(_ sender: Any) {
        UpdateExternalResourceAction.run()
    }

    @IBAction func actionQuit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }

    @IBAction func actionMoreSetting(_ sender: Any) {
        ClashWindowController<SettingTabViewController>.create().showWindow(sender)
    }
}

// MARK: Streaming Info

extension AppDelegate: ApiRequestStreamDelegate {
    func didUpdateTraffic(up: Int, down: Int) {
        statusItemView.updateSpeedLabel(up: up, down: down)
    }

    func didGetLog(log: String, level: String) {
        Logger.log(log, level: ClashLogLevel(rawValue: level) ?? .unknow)
    }
}

// MARK: Help actions

extension AppDelegate {
    @IBAction func actionShowLog(_ sender: Any?) {
        NSWorkspace.shared.openFile(Logger.shared.logFilePath())
    }
}

// MARK: Config actions

extension AppDelegate {
    @IBAction func openConfigFolder(_ sender: Any) {
        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getUrl {
                url in
                if let url = url {
                    NSWorkspace.shared.open(url)
                }
            }
        } else {
            NSWorkspace.shared.openFile(kConfigFolderPath)
        }
    }

    @IBAction func actionUpdateConfig(_ sender: AnyObject) {
        updateConfig()
    }

    @IBAction func actionSetLogLevel(_ sender: NSMenuItem) {
        let level = ClashLogLevel(rawValue: sender.title.lowercased()) ?? .unknow
        ConfigManager.selectLoggingApiLevel = level
        updateLoggingLevel()
        resetStreamApi()
    }

    @IBAction func actionAutoUpdateRemoteConfig(_ sender: Any) {
        RemoteConfigManager.autoUpdateEnable = !RemoteConfigManager.autoUpdateEnable
        remoteConfigAutoupdateMenuItem.state = RemoteConfigManager.autoUpdateEnable ? .on : .off
    }

    @IBAction func actionUpdateRemoteConfig(_ sender: Any) {
        RemoteConfigManager.shared.updateCheck(ignoreTimeLimit: true, showNotification: true)
    }

    @IBAction func actionSetUpdateInterval(_ sender: Any) {
        RemoteConfigManager.showAdd()
    }

}

// MARK: Meta Update Notification
extension AppDelegate {
	func showUpdateNotification(_ udString: String, info: String) {
		guard !UserDefaults.standard.bool(forKey: udString) else { return }
		
		UserDefaults.standard.set(true, forKey: udString)
		
		NSUserNotificationCenter.default
			.postNotificationAlert(title: "Update Tips", info: info)
	}
	
}

// MARK: Meta Menu

extension AppDelegate {
    @IBAction func actionSetTunMode(_ sender: NSMenuItem?) {
        let enable = tunModeMenuItem.state != .on
		tunModeMenuItem.isEnabled = false
        ApiRequest.updateTun(enable: enable) {
            self.syncConfigWithTun {
				self.tunModeMenuItem.state = enable ? .on : .off
				self.tunModeMenuItem.isEnabled = true
            }
        }
    }

    @IBAction func checkForUpdate(_ sender: NSMenuItem) {
        let unc = NSUserNotificationCenter.default
        AF.request("https://api.github.com/repos/MetaCubeX/ClashX.Meta/releases/latest").responseString {
            guard $0.error == nil,
                  let data = $0.data,
                  let tagName = try? JSON(data: data)["tag_name"].string else {
                unc.postUpdateNotice(msg: NSLocalizedString("Some thing failed.", comment: ""))
                return
            }

            if tagName != AppVersionUtil.currentVersion {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Open github release page to download ", comment: "") + "\(tagName)"
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(.init(string: "https://github.com/MetaCubeX/ClashX.Meta/releases/latest")!)
                }
            } else {
                unc.postUpdateNotice(msg: NSLocalizedString("No new release found.", comment: ""))
            }
        }
    }

    @IBAction func updateGEO(_ sender: NSMenuItem) {
		guard updateGeoTimer == nil else { return }
		updateGeoTimer = Timer.scheduledTimer(withTimeInterval: 500, repeats: true) { [weak self] timer in
			
			timer.fireDate = .init(timeIntervalSinceNow: 5)
			
			ApiRequest.getRules { rules in
				guard self?.updateGeoTimer != nil else { return }
				if let rule = rules.first,
				   rule.payload == ClashMetaConfig.initRulePayload {
					Logger.log("Update GEO Finished.")
					self?.updateConfig(showNotification: false) { _ in
						NSUserNotificationCenter.default.post(title: "Update GEO Databases Finished.", info: "")
					}
					
					timer.invalidate()
					self?.updateGeoTimer = nil
				} else {
					timer.fireDate = .init(timeIntervalSinceNow: 0.5)
				}
			}
		}
		
        ApiRequest.updateGEO { _ in
            NSUserNotificationCenter.default.post(title: NSLocalizedString("Updating GEO Databases...", comment: ""), info: NSLocalizedString("Good luck to you  🙃", comment: ""))
			
			self.updateGeoTimer?.fire()
        }
    }

    @IBAction func flushFakeipCache(_ sender: NSMenuItem) {
        ApiRequest.flushFakeipCache {
            NSUserNotificationCenter.default.post(title: NSLocalizedString("Flush fake-ip cache", comment: ""), info: $0 ? "Success" : "Failed")
        }
    }

    @IBAction func updateSniffing(_ sender: NSMenuItem) {
        let enable = sender.state != .on
        ApiRequest.updateSniffing(enable: enable) {
            sender.state = enable ? .on : .off
        }
    }
}

// MARK: crash hanlder

extension AppDelegate {
    func registCrashLogger() {
        /*
        #if DEBUG
            return
        #else
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                AppCenter.start(withAppSecret: "dce6e9a3-b6e3-4fd2-9f2d-35c767a99663", services: [
                    Analytics.self,
                    Crashes.self
                ])
            }

        #endif
         */
    }

    func failLaunchProtect() {
        #if DEBUG
            return
        #else
            UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": false])
            let x = UserDefaults.standard
            var launch_fail_times = 0
            if let xx = x.object(forKey: "launch_fail_times") as? Int { launch_fail_times = xx }
            launch_fail_times += 1
            x.set(launch_fail_times, forKey: "launch_fail_times")
            if launch_fail_times > 3 {
                // 发生连续崩溃
                ConfigFileManager.backupAndRemoveConfigFile()
				let ruleFiles = ClashResourceManager.RuleFiles.self

				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.mmdb.rawValue)
				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geosite.rawValue)
				try? FileManager.default.removeItem(atPath: kConfigFolderPath + ruleFiles.geoip.rawValue)

                if let domain = Bundle.main.bundleIdentifier {
                    UserDefaults.standard.removePersistentDomain(forName: domain)
                    UserDefaults.standard.synchronize()
                }
                NSUserNotificationCenter.default.post(title: "Fail on launch protect", info: "You origin Config has been renamed", notiOnly: false)
            }
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + Double(Int64(5 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                x.set(0, forKey: "launch_fail_times")
            }
        #endif
    }
}

// MARK: Memory

extension AppDelegate {
    func selectProxyGroupWithMemory() {
        let copy = [SavedProxyModel](ConfigManager.selectedProxyRecords)
        for item in copy {
            guard item.config == ConfigManager.selectConfigName else { continue }
            Logger.log("Auto selecting \(item.group) \(item.selected)", level: .debug)
            ApiRequest.updateProxyGroup(group: item.group, selectProxy: item.selected) { success in
                if !success {
                    ConfigManager.selectedProxyRecords.removeAll { model -> Bool in
                        return model.key == item.key
                    }
                }
            }
        }
    }

    func removeUnExistProxyGroups() {
        let action: (([String]) -> Void) = { list in
            let unexists = ConfigManager.selectedProxyRecords.filter {
                !list.contains($0.config)
            }
            ConfigManager.selectedProxyRecords.removeAll {
                unexists.contains($0)
            }
        }

        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getConfigFilesList { list in
                action(list)
            }
        } else {
            let list = ConfigManager.getConfigFilesList()
            action(list)
        }
    }

    func selectOutBoundModeWithMenory() {
        ApiRequest.updateOutBoundMode(mode: ConfigManager.selectOutBoundMode) {
            [weak self] _ in
            ConnectionManager.closeAllConnection()
            self?.syncConfig()
        }
    }

    func selectAllowLanWithMenory() {
        ApiRequest.updateAllowLan(allow: ConfigManager.allowConnectFromLan) {
            [weak self] in
            self?.syncConfig()
        }
    }

    func hasMenuSelected() -> Bool {
        if #available(macOS 11, *) {
            return statusMenu.items.contains { $0.state == .on }
        } else {
            return true
        }
    }
}

// MARK: NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard ConfigManager.shared.isRunning else { return }
        MenuItemFactory.refreshExistingMenuItems()
        updateConfigFiles()
        syncConfig()
        NotificationCenter.default.post(name: .proxyMeneViewShowLeftPadding,
                                        object: nil,
                                        userInfo: ["show": hasMenuSelected()])
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: item)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menu.items.forEach {
            ($0.view as? ProxyGroupMenuHighlightDelegate)?.highlight(item: nil)
        }
    }
}

// MARK: URL Scheme

extension AppDelegate {
    @objc func handleURL(event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }

        guard let components = URLComponents(string: url),
              let scheme = components.scheme,
              scheme.hasPrefix("clash"),
              let host = components.host
        else { return }

        if host == "install-config" {
            guard let url = components.queryItems?.first(where: { item in
                item.name == "url"
            })?.value else { return }

            var userInfo = ["url": url]
            if let name = components.queryItems?.first(where: { item in
                item.name == "name"
            })?.value {
                userInfo["name"] = name
            }

            remoteConfigAutoupdateMenuItem.menu?.performActionForItem(at: 0)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: Notification.Name(rawValue: "didGetUrl"), object: nil, userInfo: userInfo)
            }
        } else if host == "update-config" {
            updateConfig()
        }
    }
}
