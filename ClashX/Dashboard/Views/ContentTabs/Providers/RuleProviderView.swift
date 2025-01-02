//
//  RuleProviderView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct RuleProviderView: View {
	
	@State var provider: DBRuleProvider
	
    var body: some View {
        
		VStack(alignment: .leading) {
			HStack {
				Text(provider.name)
					.font(.title2)
					.fontWeight(.medium)
				Text(provider.type)
				Text(provider.behavior)
				Spacer()
			}
			
			HStack {
				Text("\(provider.ruleCount) rules")
                Text("Updated \(RelativeDateTimeFormatter().localizedString(for: provider.updatedAt, relativeTo: Date()))")
				Spacer()
			}
			.font(.system(size: 12))
			.foregroundColor(.secondary)
		}
    }
}

//struct RuleProviderView_Previews: PreviewProvider {
//    static var previews: some View {
//        RuleProviderView()
//    }
//}
