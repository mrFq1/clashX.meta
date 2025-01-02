//
//  ProxiesView.swift
//  ClashX Dashboard
//
//

import SwiftUI
import SwiftUIIntrospect

class ProxiesSearchString: ObservableObject, Identifiable {
	let id = UUID().uuidString
	@Published var string: String = ""
}

struct ProxiesView: View {
	
	@ObservedObject var proxyStorage = DBProxyStorage()
	
	@State private var searchString = ProxiesSearchString()
	@State private var isGlobalMode = false
	
	@StateObject private var hideProxyNames = HideProxyNames()
	
    var body: some View {
		NavigationView {
            List(proxyStorage.groups.filter({ !$0.hidden }), id: \.id) { group in
				ProxyGroupRowView(proxyGroup: group)
			}
			.introspect(.table, on: .macOS(.v12, .v13, .v14, .v15)) {
				$0.refusesFirstResponder = true
				$0.doubleAction = nil
			}
			.listStyle(.plain)
			EmptyView()
		}
        .background(Color("SwiftUI Colors/WindowBackgroundColor"))
		.onReceive(NotificationCenter.default.publisher(for: .toolbarSearchString)) {
			guard let string = $0.userInfo?["String"] as? String else { return }
			searchString.string = string
		}
		.onReceive(NotificationCenter.default.publisher(for: .hideNames)) {
			guard let hide = $0.userInfo?["hide"] as? Bool else { return }
			hideProxyNames.hide = hide
		}
		.environmentObject(searchString)
		.onAppear {
			loadProxies()
		}
		.environmentObject(hideProxyNames)
    }
	
	
	func loadProxies() {
//			self.isGlobalMode = ConfigManager.shared.currentConfig?.mode == .global
		ApiRequest.getMergedProxyData {
			guard let resp = $0 else { return }
			proxyStorage.groups = DBProxyStorage(resp).groups.filter {
				isGlobalMode ? true : $0.name != "GLOBAL"
			}
		}
	}
}

//struct ProxiesView_Previews: PreviewProvider {
//    static var previews: some View {
//        ProxiesView()
//    }
//}
