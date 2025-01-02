//
//  MenuItemFactory.swift
//  ClashX
//
//  Created by CYC on 2018/8/4.
//  Copyright © 2018年 yichengchen. All rights reserved.
//

import Cocoa
import RxCocoa
import SwiftyJSON

class MenuItemFactory {
    private static var cachedProxyData: ClashProxyResp?

	static var useViewToRenderProxy: Bool = AppDelegate.isAboveMacOS152

    static var hideUnselectable: Int = UserDefaults.standard.object(forKey: "hideUnselectable") as? Int ?? NSControl.StateValue.off.rawValue {
        didSet {
            UserDefaults.standard.set(hideUnselectable, forKey: "hideUnselectable")
            recreateProxyMenuItems()
        }
    }
	

    static let updateAllProvidersTitle = NSLocalizedString("Update All Providers", comment: "")

    // MARK: - Public

    static func refreshExistingMenuItems() {
        ApiRequest.getMergedProxyData {
            info in
            if info?.proxiesMap.keys != cachedProxyData?.proxiesMap.keys {
                // force update menu
                refreshMenuItems(mergedData: info)
                return
            }

            for proxy in info?.proxies ?? [] {
                NotificationCenter.default.post(name: .proxyUpdate(for: proxy.name), object: proxy, userInfo: nil)
            }
        }
    }

    static func recreateProxyMenuItems() {
        ApiRequest.getMergedProxyData {
            proxyInfo in
            cachedProxyData = proxyInfo
            refreshMenuItems(mergedData: proxyInfo)
        }
    }

    static func recreateRuleProvidersMenuItems() {
        ApiRequest.requestRuleProviderList {
            refreshRuleProviderMenuItems($0.allProviders.map({ $0.value }))
        }
    }

    static func refreshMenuItems(mergedData proxyInfo: ClashProxyResp?) {
        let leftPadding = AppDelegate.shared.hasMenuSelected()
        guard let proxyInfo = proxyInfo else { return }

        let hideState = NSControl.StateValue(rawValue: hideUnselectable)

        var menuItems = [NSMenuItem]()
        var collapsedItems = [NSMenuItem]()

        for proxy in proxyInfo.proxyGroups {
            var menu: NSMenuItem?
            switch proxy.type {
            case .select: menu = generateSelectorMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .urltest, .fallback: menu = generateUrlTestFallBackMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .loadBalance:
                menu = generateLoadBalanceMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo, leftPadding: leftPadding)
            case .relay:
                menu = generateListOnlyMenuItem(proxyGroup: proxy, proxyInfo: proxyInfo)
            default: continue
            }

            guard let menu = menu else {
                continue
            }
			
			if let hidden = proxy.hidden, hidden {
				continue
			}

            switch hideState {
            case .mixed where [.urltest, .fallback, .loadBalance, .relay].contains(proxy.type):
                collapsedItems.append(menu)
                menu.isEnabled = true
            case .on where [.urltest, .fallback, .loadBalance, .relay].contains(proxy.type):
                continue
            default:
                menuItems.append(menu)
                menu.isEnabled = true
            }
        }

        if hideState == .mixed {
            let collapsedItem = NSMenuItem(title: "Collapsed", action: nil, keyEquivalent: "")
            collapsedItem.isEnabled = true
            collapsedItem.submenu = .init(title: "")
            collapsedItem.submenu?.items = collapsedItems

            menuItems.append(collapsedItem)
        }

        let items = Array(menuItems.reversed())
        updateProxyList(withMenus: items)

        refreshProxyProviderMenuItems(mergedData: proxyInfo)
        recreateRuleProvidersMenuItems()
    }

    static func generateSwitchConfigMenuItems(complete: @escaping (([NSMenuItem]) -> Void)) {
        let generateMenuItem: ((String) -> NSMenuItem) = {
            config in
            let item = NSMenuItem(title: config, action: #selector(MenuItemFactory.actionSelectConfig(sender:)), keyEquivalent: "")
            item.target = MenuItemFactory.self
            item.state = ConfigManager.selectConfigName == config ? .on : .off
            return item
        }

        if RemoteControlManager.selectConfig != nil {
            complete([])
            return
        }

        if ICloudManager.shared.useiCloud.value {
            ICloudManager.shared.getConfigFilesList {
                complete($0.map { generateMenuItem($0) })
            }
        } else {
            complete(ConfigManager.getConfigFilesList().map { generateMenuItem($0) })
        }
    }

    // MARK: - Private

    // MARK: Updaters

    static func updateProxyList(withMenus menus: [NSMenuItem]) {
        let app = AppDelegate.shared
        let startIndex = app.statusMenu.items.firstIndex(of: app.separatorLineTop)! + 1
        let endIndex = app.statusMenu.items.firstIndex(of: app.sepatatorLineEndProxySelect)!
        app.sepatatorLineEndProxySelect.isHidden = menus.isEmpty
        for _ in 0 ..< endIndex - startIndex {
            app.statusMenu.removeItem(at: startIndex)
        }
        for each in menus {
            app.statusMenu.insertItem(each, at: startIndex)
        }
    }

    // MARK: Generators

    private static func generateSelectorMenuItem(proxyGroup: ClashProxy,
                                                 proxyInfo: ClashProxyResp,
                                                 leftPadding: Bool) -> NSMenuItem? {
        let proxyMap = proxyInfo.proxiesMap

        let isGlobalMode = ConfigManager.shared.currentConfig?.mode == .global
        if !isGlobalMode {
            if proxyGroup.name == "GLOBAL" { return nil }
        }

        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        let selectedName = proxyGroup.now ?? ""
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: selectedName, hasLeftPadding: leftPadding)
        }
        let submenu = ProxyGroupMenu(title: proxyGroup.name)

        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(MenuItemFactory.actionSelectProxy(sender:)))
            proxyItem.target = MenuItemFactory.self
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }

        if proxyGroup.isSpeedTestable && useViewToRenderProxy {
            submenu.minimumWidth = proxyGroup.maxProxyNameLength + ProxyItemView.fixedPlaceHolderWidth
        }

        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
        menu.submenu = submenu
        return menu
    }

    private static func generateUrlTestFallBackMenuItem(proxyGroup: ClashProxy,
                                                        proxyInfo: ClashProxyResp,
                                                        leftPadding: Bool) -> NSMenuItem? {
        let proxyMap = proxyInfo.proxiesMap
        let selectedName = proxyGroup.now ?? ""
        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: selectedName, hasLeftPadding: leftPadding)
        }
        let submenu = NSMenu(title: proxyGroup.name)

        for proxyName in proxyGroup.all ?? [] {
            guard let proxy = proxyMap[proxyName] else { continue }
            let proxyMenuItem = ProxyMenuItem(proxy: proxy, group: proxyGroup, action: #selector(empty), simpleItem: true)
            proxyMenuItem.target = MenuItemFactory.self
            if proxy.name == selectedName {
                proxyMenuItem.state = .on
            }

            proxyMenuItem.submenu = ProxyDelayHistoryMenu(proxy: proxy)

            submenu.addItem(proxyMenuItem)
        }
        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
        menu.submenu = submenu
        return menu
    }

    private static func addSpeedTestMenuItem(_ menu: NSMenu, proxyGroup: ClashProxy) {
        guard !proxyGroup.speedtestAble.isEmpty else { return }
        let speedTestItem = ProxyGroupSpeedTestMenuItem(group: proxyGroup)
        let separator = NSMenuItem.separator()
        menu.insertItem(separator, at: 0)
        menu.insertItem(speedTestItem, at: 0)
        (menu as? ProxyGroupMenu)?.add(delegate: speedTestItem)
    }

    private static func generateLoadBalanceMenuItem(proxyGroup: ClashProxy, proxyInfo: ClashProxyResp, leftPadding: Bool) -> NSMenuItem? {
        let proxyMap = proxyInfo.proxiesMap

        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        if !Settings.disableShowCurrentProxyInMenu {
            menu.view = ProxyGroupMenuItemView(group: proxyGroup.name, targetProxy: NSLocalizedString("Load Balance", comment: ""), hasLeftPadding: leftPadding, observeUpdate: false)
        }
        let submenu = ProxyGroupMenu(title: proxyGroup.name)

        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(empty))
            proxyItem.target = MenuItemFactory.self
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }
        if proxyGroup.isSpeedTestable && useViewToRenderProxy {
            submenu.minimumWidth = proxyGroup.maxProxyNameLength + ProxyItemView.fixedPlaceHolderWidth
        }
        addSpeedTestMenuItem(submenu, proxyGroup: proxyGroup)
        menu.submenu = submenu

        return menu
    }

    private static func generateListOnlyMenuItem(proxyGroup: ClashProxy, proxyInfo: ClashProxyResp) -> NSMenuItem? {
        let menu = NSMenuItem(title: proxyGroup.name, action: nil, keyEquivalent: "")
        let submenu = ProxyGroupMenu(title: proxyGroup.name)
        let proxyMap = proxyInfo.proxiesMap

        for proxy in proxyGroup.all ?? [] {
            guard let proxyModel = proxyMap[proxy] else { continue }
            let proxyItem = ProxyMenuItem(proxy: proxyModel,
                                          group: proxyGroup,
                                          action: #selector(empty),
                                          simpleItem: true)
            proxyItem.target = MenuItemFactory.self
            submenu.add(delegate: proxyItem)
            submenu.addItem(proxyItem)
        }
        menu.submenu = submenu
        return menu
    }
}

// MARK: - Experimental

extension MenuItemFactory {
    static func addExperimentalMenuItem(_ menu: inout NSMenu) {
        let useViewRender = NSMenuItem(title: NSLocalizedString("Enhance proxy list render", comment: ""), action: #selector(optionUseViewRenderMenuItemTap(sender:)), keyEquivalent: "")
        useViewRender.target = self
        menu.addItem(useViewRender)
        updateUseViewRenderMenuItem(useViewRender)
    }

    static func updateUseViewRenderMenuItem(_ item: NSMenuItem) {
        item.state = useViewToRenderProxy ? .on : .off
    }

    @objc static func optionUseViewRenderMenuItemTap(sender: NSMenuItem) {
        useViewToRenderProxy = !useViewToRenderProxy
        updateUseViewRenderMenuItem(sender)
        recreateProxyMenuItems()
    }
}

// MARK: - Meta

extension MenuItemFactory {

    static func refreshProxyProviderMenuItems(mergedData proxyInfo: ClashProxyResp?) {
        let app = AppDelegate.shared
        guard let proxyInfo = proxyInfo,
              let menu = app.proxyProvidersMenu,
              let providers = proxyInfo.enclosingProviderResp
        else { return }

        let proxyProviders = providers.allProviders.filter {
            $0.value.vehicleType == .HTTP
        }.values.sorted(by: { $0.name < $1.name })

        let isEmpty = proxyProviders.count == 0
        app.proxyProvidersMenuItem.isEnabled = !isEmpty
        guard !isEmpty else { return }

        initUpdateAllProvidersMenuItem(for: menu, type: .proxy)
        let maxNameLength = maxProvidersLength(for: proxyProviders.map({ $0.name }))
        proxyProviders.forEach { provider in
            let item = DualTitleMenuItem(
                provider.name,
                subTitle: providerUpdateTitle(provider.updatedAt),
                action: #selector(actionUpdateSelectProvider),
                maxLength: maxNameLength)
            item.tag = ApiRequest.ProviderType.proxy.rawValue
            item.target = self
            menu.addItem(item)
        }
    }

    static func refreshRuleProviderMenuItems(_ ruleProviders: [ClashRuleProvider]) {
        let app = AppDelegate.shared
        
        let ruleProviders = ruleProviders.filter {
            $0.vehicleType == .HTTP
        }
        let isEmpty = ruleProviders.count == 0
        app.ruleProvidersMenuItem.isEnabled = !isEmpty

        guard !isEmpty,
              let menu = app.ruleProvidersMenu
        else { return }

        initUpdateAllProvidersMenuItem(for: menu, type: .rule)
        let maxNameLength = maxProvidersLength(for: ruleProviders.map({ $0.name }))
        ruleProviders.sorted(by: { $0.name < $1.name })
            .forEach { provider in
                let item = DualTitleMenuItem(
                    provider.name,
                    subTitle: providerUpdateTitle(provider.updatedAt),
                    action: #selector(actionUpdateSelectProvider),
                    maxLength: maxNameLength)
                item.tag = ApiRequest.ProviderType.rule.rawValue
                item.target = self
                menu.addItem(item)
            }
    }

    static func initUpdateAllProvidersMenuItem(for menu: NSMenu, type: ApiRequest.ProviderType) {
        if menu.items.count > 1 {
            menu.items.enumerated().filter {
                $0.offset > 1
            }.forEach {
                menu.removeItem($0.element)
            }
        } else {
            let updateAllItem = NSMenuItem(title: updateAllProvidersTitle, action: #selector(actionUpdateAllProviders), keyEquivalent: "")
            updateAllItem.tag = type.rawValue
            updateAllItem.target = self
            menu.addItem(updateAllItem)
            menu.addItem(.separator())
        }
    }

    static func maxProvidersLength(for names: [String]) -> CGFloat {
        func getLength(_ string: String) -> CGFloat {
            let rect = CGSize(width: CGFloat.greatestFiniteMagnitude, height: 20)
            let attr = [NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 14)]
            let length = (string as NSString)
                .boundingRect(with: rect,
                              options: .usesLineFragmentOrigin,
                              attributes: attr).width
            return length
        }

        var lengths = names.map {
            getLength($0) + 65
        }
        lengths.append(getLength(updateAllProvidersTitle))
        return lengths.max() ?? 0
    }

    static func providerUpdateTitle(_ updatedAt: Date?) -> String? {
        let dateCF = DateComponentsFormatter()
        dateCF.allowedUnits = [.day, .hour, .minute]
        dateCF.maximumUnitCount = 1
        dateCF.unitsStyle = .abbreviated
        dateCF.zeroFormattingBehavior = .dropAll

        guard let date = updatedAt,
			  !date.timeIntervalSinceNow.isNaN,
              !date.timeIntervalSinceNow.isInfinite,
              let re = dateCF.string(from: abs(date.timeIntervalSinceNow)) else { return nil }

        return re + NSLocalizedString(" ago", comment: "Provider update time title")
    }

    @objc static func actionUpdateAllProviders(sender: NSMenuItem) {
        let type = ApiRequest.ProviderType(rawValue: sender.tag)!
        let s = "Update All \(type.logString()) Providers"
        Logger.log(s)
        ApiRequest.updateAllProviders(for: type) {
            Logger.log("\(s) \($0) failed")
            let info = $0 == 0 ? "Success" : "\($0) failed"
			UserNotificationCenter.shared.post(title: s, info: info)
            recreateProxyMenuItems()
        }
    }

    @objc static func actionUpdateSelectProvider(sender: DualTitleMenuItem) {
        let name = sender.originTitle
        let type = ApiRequest.ProviderType(rawValue: sender.tag)!

        let log = "Update \(type.logString()) Provider \(name)"
        Logger.log(log)
        ApiRequest.updateProvider(for: type, name: name) {
            let info = $0 ? "Success" : "Failed"
            Logger.log("\(log) info")
			UserNotificationCenter.shared.post(title: log, info: info)
            recreateProxyMenuItems()
        }
    }
}

// MARK: - Action

extension MenuItemFactory {
    @objc static func actionSelectProxy(sender: ProxyMenuItem) {
        guard let proxyGroup = sender.menu?.title else { return }
        let proxyName = sender.proxyName

        ApiRequest.updateProxyGroup(group: proxyGroup, selectProxy: proxyName) { success in
            if success {
                for items in sender.menu?.items ?? [NSMenuItem]() {
                    items.state = .off
                }
                sender.state = .on
                // remember select proxy
                let newModel = SavedProxyModel(group: proxyGroup, selected: proxyName, config: ConfigManager.selectConfigName)
                ConfigManager.selectedProxyRecords.removeAll { model -> Bool in
                    return model.key == newModel.key
                }
                ConfigManager.selectedProxyRecords.append(newModel)
                // terminal Connections for this group
                ConnectionManager.closeConnection(for: proxyGroup)
                // refresh menu items
                MenuItemFactory.refreshExistingMenuItems()
            }
        }
    }

    @objc static func actionSelectConfig(sender: NSMenuItem) {
        let config = sender.title
        AppDelegate.shared.updateConfig(configName: config, showNotification: false) {
            err in
            if err == nil {
                ConnectionManager.closeAllConnection()
            }
        }
    }

    @objc static func empty() {}
}
