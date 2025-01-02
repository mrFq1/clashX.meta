//
//  ProxyProvidersRowView.swift
//  ClashX Dashboard
//
//

import SwiftUI

struct ProxyProvidersRowView: View {
	
	@ObservedObject var providerStorage: DBProviderStorage
	@EnvironmentObject var searchString: ProxiesSearchString
	
	@State private var isUpdating = false
	
	var providers: [DBProxyProvider] {
        var pp = [DBProxyProvider]()
		if searchString.string.isEmpty {
            pp = providerStorage.proxyProviders
		} else {
            pp = providerStorage.proxyProviders.filter {
				$0.name.lowercased().contains(searchString.string.lowercased())
			}
		}
        return pp.filter {
            $0.vehicleType == .HTTP
        }
	}
	
    var body: some View {
		NavigationLink {
			contentView
		} label: {
			Text("Proxy")
				.font(.system(size: 15))
				.padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
		}
    }
	
	var contentView: some View {
		ScrollView {
			Section {
				VStack(spacing: 16) {
					listView
				}
			} header: {
				ProgressButton(
					title: "Update All",
					title2: "Updating",
					iconName: "arrow.clockwise", inProgress: $isUpdating) {
						updateAll()
					}
			}
			.padding()
		}
	}
	
	var listView: some View {
        ForEach(providers, id: \.id) { provider in
			ProxyProviderInfoView(provider: provider, withUpdateButton: true)
		}
	}
	
	func updateAll() {
		isUpdating = true
		
		ApiRequest.updateAllProviders(for: .proxy) { _ in
			ApiRequest.requestProxyProviderList { resp in
				providerStorage.proxyProviders = resp.allProviders.values.filter {
					$0.vehicleType == .HTTP
				}.sorted {
					$0.name < $1.name
				}
				.map(DBProxyProvider.init)
				isUpdating = false
			}
		}
	}
}

//struct AllProvidersRowView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProxyProvidersRowView()
//    }
//}
