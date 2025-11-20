//
//  AuthenticationManager.swift
//  KickTest
//
//  Created by Kevin Cohen on 2025-11-20.
//

import Foundation
import Combine
import AuthenticationServices
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var user: KickUser?
    @Published var showSuccessMessage = false
    @Published var errorMessage: String?
    
    // Kick OAuth credentials
    // SECURITY WARNING: Client secret is embedded in the app. For production, consider:
    // - Using PKCE flow if Kick supports it (no client secret needed)
    // - Storing secret in secure keychain
    // - Using a backend proxy for token exchange
    private let clientId = "01KAHF2SRWZKACQYSDGAF5SXDF"
    private let clientSecret = "262aebfafe8c253680dc636f5b8df3e3de69bcd4fbc9a78520751c27d70d848d"
    
    // Kick requires HTTPS redirect URIs
    // CRITICAL: This EXACT string (including path, trailing slash, etc.) must match
    // what's registered in Kick's developer portal. Even one character difference causes
    // Kick to redirect to homepage instead of showing the login/consent screen.
    // Use the SAME literal string in both authorize and token exchange calls.
    private let redirectURI = "https://kicktest123.pages.dev"
    private let authURL = "https://kick.com/oauth/authorize"
    private let tokenURL = "https://kick.com/oauth/token"
    private let apiBaseURL = "https://kick.com/api/v1"
    
    private var webAuthSession: ASWebAuthenticationSession?
    
    func signIn() {
        errorMessage = nil
        guard let url = buildAuthorizationURL() else {
            errorMessage = "Failed to build authorization URL"
            print("Failed to build authorization URL")
            return
        }
        
        print("🔐 Opening OAuth URL: \(url.absoluteString)")
        
        // Use the HTTPS redirect URI scheme for the callback
        // The web page will redirect to kicktest:// which our app will handle
        let callbackScheme = redirectURI.hasPrefix("https://") ? "kicktest" : redirectURI.components(separatedBy: "://").first ?? "kicktest"
        
        webAuthSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme,
            completionHandler: { [weak self] callbackURL, error in
                guard let self = self else { return }
                
                if let error = error {
                    let errorCode = (error as NSError).code
                    if errorCode == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        print("❌ User canceled authentication")
                        Task { @MainActor in
                            self.errorMessage = "Sign in was canceled"
                        }
                    } else {
                        print("❌ Authentication error: \(error.localizedDescription)")
                        print("❌ Error code: \(errorCode)")
                        Task { @MainActor in
                            self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                        }
                    }
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    print("❌ No callback URL received")
                    Task { @MainActor in
                        self.errorMessage = "No callback received from authentication"
                    }
                    return
                }
                
                print("📱 Received callback URL: \(callbackURL.absoluteString)")
                
                // Parse URL components first
                guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true) else {
                    print("❌ Failed to parse callback URL: \(callbackURL.absoluteString)")
                    Task { @MainActor in
                        self.errorMessage = "Invalid callback URL format"
                    }
                    return
                }
                
                // Check for error in callback
                if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                    let errorDescription = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
                    print("❌ OAuth error in callback: \(error) - \(errorDescription)")
                    Task { @MainActor in
                        self.errorMessage = "OAuth error: \(errorDescription)"
                    }
                    return
                }
                
                // Extract authorization code
                guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    print("❌ Failed to extract authorization code from: \(callbackURL.absoluteString)")
                    print("❌ Available query items: \(components.queryItems ?? [])")
                    Task { @MainActor in
                        self.errorMessage = "Failed to extract authorization code. Check console for details."
                    }
                    return
                }
                
                print("✅ Authorization code received, exchanging for token...")
                Task {
                    await self.exchangeCodeForToken(code: code)
                }
            }
        )
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.prefersEphemeralWebBrowserSession = false
        webAuthSession?.start()
    }
    
    func signOut() {
        accessToken = nil
        user = nil
        isAuthenticated = false
        showSuccessMessage = false
        errorMessage = nil
    }
    
    private func buildAuthorizationURL() -> URL? {
        var components = URLComponents(string: authURL)
        
        // CRITICAL: Use the EXACT redirectURI value (no trimming, no modification)
        // It must match character-for-character what's in Kick's developer portal
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI), // Use exact value
            URLQueryItem(name: "scope", value: "user:read channel:read"),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        let url = components?.url
        print("🔗 Built authorization URL: \(url?.absoluteString ?? "nil")")
        print("📋 Redirect URI being used: \(redirectURI)")
        print("⚠️  CRITICAL: This EXACT redirect URI must match Kick's portal (character-for-character)!")
        return url
    }
    
    private func exchangeCodeForToken(code: String) async {
        guard let url = URL(string: tokenURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "client_secret": clientSecret
        ]
        
        let bodyString = bodyParams
            .map { "\($0.key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Failed to exchange code for token")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                print("✅ Access token received successfully")
                await MainActor.run {
                    self.accessToken = token
                    self.isAuthenticated = true
                }
                
                await fetchUserProfile()
            } else {
                print("❌ Failed to parse access token from response")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }
                await MainActor.run {
                    self.errorMessage = "Failed to get access token"
                }
            }
        } catch {
            print("Error exchanging code for token: \(error.localizedDescription)")
        }
    }
    
    private func fetchUserProfile() async {
        guard let token = accessToken,
              let url = URL(string: "\(apiBaseURL)/user") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let userData = try? JSONDecoder().decode(KickUser.self, from: data) {
                print("✅ User profile fetched: \(userData.username ?? "unknown")")
                await MainActor.run {
                    self.user = userData
                    self.showSuccessMessage = true
                    // Hide success message after 3 seconds
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            self.showSuccessMessage = false
                        }
                    }
                }
            } else {
                print("❌ Failed to decode user profile")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Response: \(responseString)")
                }
            }
        } catch {
            print("Error fetching user profile: \(error.localizedDescription)")
        }
    }
}

extension AuthenticationManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS) || os(visionOS)
        // Get the first connected window scene for iOS/visionOS
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        #elseif os(macOS)
        // For macOS, get the key window
        if let window = NSApplication.shared.keyWindow {
            return window
        }
        #endif
        
        // Fallback: get any available window
        #if os(iOS) || os(visionOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        #elseif os(macOS)
        if let window = NSApplication.shared.windows.first {
            return window
        }
        #endif
        
        // This should never happen in normal operation, but we need to return something
        // In practice, a window should always be available when this is called
        #if os(iOS) || os(visionOS)
        // Try to get any window from any scene as last resort
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.windows.first ?? windowScene.keyWindow ?? windowScene.windows.first ?? UIApplication.shared.windows.first ?? UIWindow(frame: .zero)
        }
        return UIApplication.shared.windows.first ?? UIWindow(frame: .zero)
        #elseif os(macOS)
        return NSApplication.shared.windows.first ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

struct KickUser: Codable {
    let id: Int?
    let username: String?
    let email: String?
    let bio: String?
    let profilePicture: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case bio
        case profilePicture = "profile_picture"
    }
}

