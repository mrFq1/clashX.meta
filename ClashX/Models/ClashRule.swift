//
//  ClashRule.swift
//  ClashX
//
//  Created by CYC on 2018/10/27.
//  Copyright © 2018 west2online. All rights reserved.
//

import Foundation

class ClashRule: NSObject, Codable, Identifiable {
	@objc let type: String
	@objc let payload: String?
	@objc let proxy: String?
	@objc var size: Int
	
	init(type: String, payload: String?, proxy: String?) {
		self.type = type
		self.payload = payload
		self.proxy = proxy
		self.size = -1
	}
}


class ClashRuleResponse: Codable {
    var rules: [ClashRule]?

    static func empty() -> ClashRuleResponse {
        return ClashRuleResponse()
    }

    static func fromData(_ data: Data) -> ClashRuleResponse {
        let decoder = JSONDecoder()
        let model = try? decoder.decode(ClashRuleResponse.self, from: data)
        return model ?? ClashRuleResponse.empty()
    }
}
