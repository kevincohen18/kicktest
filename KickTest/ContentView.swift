//
//  ContentView.swift
//  KickTest
//
//  Created by Kevin Cohen on 2025-11-20.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                HomeView(authManager: authManager)
            } else {
                LoginView(authManager: authManager)
            }
        }
    }
}

#Preview {
    ContentView()
}
