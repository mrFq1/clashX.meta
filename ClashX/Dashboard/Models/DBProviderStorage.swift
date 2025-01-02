//
//  DBProviderStorage.swift
//  ClashX Dashboard
//
//

import Cocoa
import SwiftUI

class DBProviderStorage: ObservableObject {
	@Published var proxyProviders = [DBProxyProvider]()
	@Published var ruleProviders = [DBRuleProvider]()

	init() {}
	
}

class DBProxyProvider: ObservableObject, Identifiable {
	let id = UUID().uuidString
	
	@Published var name: ClashProviderName
	@Published var proxies: [DBProxy]
	@Published var type: ClashProvider.ProviderType
	@Published var vehicleType: ClashProviderVehicleType

	@Published var trafficInfo: String
	@Published var trafficPercentage: String
	@Published var expireDate: String
	@Published var updatedAt: String
	
	init(provider: ClashProvider) {
		name = provider.name
		proxies = provider.proxies.map(DBProxy.init)
		type = provider.type
		vehicleType = provider.vehicleType
		
		if let info = provider.subscriptionInfo {
			let used = info.download + info.upload
			let total = info.total
			
			let trafficRate = "\(String(format: "%.2f", Double(used)/Double(total/100)))%"
			
			let formatter = ByteCountFormatter()
			
			trafficInfo = formatter.string(fromByteCount: used)
			+ " / "
			+ formatter.string(fromByteCount: total)
			+ " ( \(trafficRate) )"
			
			let expire = info.expire
			if expire == 0 {
				expireDate = "Expire: none"
			} else {
				let eDate = Date(timeIntervalSince1970: TimeInterval(expire))
				if #available(macOS 12.0, *) {
					expireDate = "Expire: " + eDate.formatted()
				} else {
					let dateFormatter = DateFormatter()
					dateFormatter.dateStyle = .short
					dateFormatter.timeStyle = .short
					expireDate = "Expire: " + dateFormatter.string(from: eDate)
				}
			}
			
			self.trafficPercentage = trafficRate
		} else {
			trafficInfo = ""
			expireDate = ""
			trafficPercentage = "0.0%"
		}
		
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        self.updatedAt = formatter.localizedString(for: provider.updatedAt, relativeTo: Date())
	}
	
	func updateInfo(_ new: DBProxyProvider) {
		proxies = new.proxies
		updatedAt = new.updatedAt
		expireDate = new.expireDate
		trafficInfo = new.trafficInfo
		trafficPercentage = new.trafficPercentage
	}
}

class DBRuleProvider: ObservableObject, Identifiable {
	let id: String
	
	@Published var name: ClashProviderName
	@Published var ruleCount: Int
	@Published var behavior: String
	@Published var type: String
    @Published var vehicleType: ClashProviderVehicleType
	@Published var updatedAt: Date
	
	init(provider: ClashRuleProvider) {
		id = UUID().uuidString
		
		name = provider.name
		ruleCount = provider.ruleCount
		behavior = provider.behavior
		type = provider.type
        vehicleType = provider.vehicleType
		updatedAt = provider.updatedAt
	}
}
