//
//  ClashRuleProvider.swift
//  ClashX Meta

import Foundation

class ClashRuleProviderResp: Codable {
    let allProviders: [ClashProxyName: ClashRuleProvider]

    init() {
        allProviders = [:]
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.js)
        return decoder
    }

    private enum CodingKeys: String, CodingKey {
        case allProviders = "providers"
    }
}

class ClashRuleProvider: NSObject, Codable {
    
	@objc let name: ClashProviderName
	let ruleCount: Int
	@objc let behavior: String
    @objc let type: String
	let updatedAt: Date
    let vehicleType: ClashProviderVehicleType
    
    private enum CodingKeys: String, CodingKey {
        case name, ruleCount, behavior, type, updatedAt, vehicleType
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(ClashProviderName.self, forKey: .name)
        ruleCount = try container.decode(Int.self, forKey: .ruleCount)
        behavior = try container.decode(String.self, forKey: .behavior)
        type = try container.decode(String.self, forKey: .type)
        vehicleType = try container.decode(ClashProviderVehicleType.self, forKey: .vehicleType)
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? .init(timeIntervalSince1970: 0)
    }
    
}
