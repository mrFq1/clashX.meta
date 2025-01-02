//
//  ClashProvider.swift
//  ClashX
//
//  Created by yichengchen on 2019/12/14.
//  Copyright © 2019 west2online. All rights reserved.
//

import Cocoa

class ClashProviderResp: Codable {
    let allProviders: [ClashProxyName: ClashProvider]
    lazy var providers: [ClashProxyName: ClashProvider] = allProviders.filter { $0.value.vehicleType != .Compatible }

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

class ClashProvider: Codable {
    enum ProviderType: String, Codable {
        case Proxy
        case String
        case Unknown
    }

    let name: ClashProviderName
    let proxies: [ClashProxy]
    let type: ProviderType
    let vehicleType: ClashProviderVehicleType
	let updatedAt: Date

    let subscriptionInfo: ClashProviderSubInfo?
    
    
    private enum CodingKeys: String, CodingKey {
        case name, proxies, type, vehicleType, updatedAt, subscriptionInfo
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(ClashProviderName.self, forKey: .name)
        proxies = try container.decode([ClashProxy].self, forKey: .proxies)
        type = (try? container.decode(ProviderType.self, forKey: .type)) ?? .Unknown
        vehicleType = try container.decode(ClashProviderVehicleType.self, forKey: .vehicleType)
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? .init(timeIntervalSince1970: 0)
        subscriptionInfo = try? container.decode(ClashProviderSubInfo.self, forKey: .subscriptionInfo)
    }
}

enum ClashProviderVehicleType: String, Codable, CaseIterable {
    case HTTP
    case File
    case Compatible
    case Inline
    case Unknown
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawString = try container.decode(String.self)
        self = ClashProviderVehicleType.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(rawString) == .orderedSame }) ?? .Unknown
    }
}

class ClashProviderSubInfo: Codable {
	let upload: Int64
	let download: Int64
	let total: Int64
	let expire: Int

    private enum CodingKeys: String, CodingKey {
        case upload = "Upload",
             download = "Download",
             total = "Total",
             expire = "Expire"
    }
}
