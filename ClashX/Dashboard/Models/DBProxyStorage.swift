//
//  DBProxyStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI

class DBProxyStorage: ObservableObject {
	@Published var groups = [DBProxyGroup]()
	
	init() {
		
	}
	
	init(_ resp: ClashProxyResp) {
		groups = resp.proxyGroups.map {
			DBProxyGroup($0, resp: resp)
		}
	}
}

class DBProxyGroup: ObservableObject, Identifiable {
	let id = UUID().uuidString
	@Published var name: ClashProxyName
	@Published var type: ClashProxyType
	@Published var now: ClashProxyName? {
		didSet {
			currentProxy = proxies.first {
				$0.name == now
			}
		}
	}
	
	@Published var proxies: [DBProxy]
	@Published var currentProxy: DBProxy?
	
    @Published var hidden: Bool
    
	init(_ group: ClashProxy, resp: ClashProxyResp) {
		name = group.name
		type = group.type
		now = group.now
        hidden = group.hidden ?? false

		proxies = group.all?.compactMap { name in
			resp.proxiesMap[name]
		}.map(DBProxy.init) ?? []
		
		currentProxy = proxies.first {
			$0.name == now
		}
	}
}

class DBProxy: ObservableObject {
	let id: String
	@Published var name: ClashProxyName
	@Published var type: ClashProxyType
	@Published var udpString: String
	@Published var tfo: Bool
	
	var delay: Int {
		didSet {
			delayString = DBProxy.delayString(delay)
			delayColor = DBProxy.delayColor(delay)
		}
	}
	
	@Published var delayString: String
	@Published var delayColor: Color
	
	init(_ proxy: ClashProxy) {
		id = proxy.id ?? UUID().uuidString
		name = proxy.name
		type = proxy.type
		tfo = proxy.tfo
		delay = proxy.history.last?.delayInt ?? 0
				
		udpString = {
			if proxy.udp {
				return "UDP"
			} else if proxy.xudp {
				return "XUDP"
			} else {
				return ""
			}
		}()
		delayString = DBProxy.delayString(delay)
		delayColor = DBProxy.delayColor(delay)
	}
	
	static func delayString(_ delay: Int) -> String {
		switch delay {
		case 0:
			return NSLocalizedString("fail", comment: "")
		default:
			return "\(delay) ms"
		}
	}
	
	static func delayColor(_ delay: Int) -> Color {
		let httpsTest = ConfigManager.shared.benchMarkUrl.hasPrefix("https://")
		
		switch delay {
		case 0:
            return .red
		case ..<200 where !httpsTest:
			return .green
		case ..<800 where httpsTest:
			return .green
		case 200..<500 where !httpsTest:
			return .yellow
		case 800..<1500 where httpsTest:
			return .yellow
		default:
			return .orange
		}
	}
}


extension String {
    var hiddenID: String {
        guard UUID(uuidString: self) != nil else { return "" }
        let components = split(separator: "-").map(String.init)
        guard components.count == 5 else { return "" }
        
        let re = components[0].prefix(2)
        + components[1].prefix(1)
        + components[2].prefix(1)
        + components[3].prefix(1)
        + components[4].suffix(3)
        
        return String(re)
    }
}
