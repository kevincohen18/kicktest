//
//  HomeView.swift
//  KickTest
//
//  Created by Kevin Cohen on 2025-11-20.
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 20) {
                    if let user = authManager.user {
                        // Success Message
                        if authManager.showSuccessMessage {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Signed in successfully as \(user.username ?? "User")")
                                    .font(.headline)
                                    .foregroundColor(.green)
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // User Profile Section
                        VStack(spacing: 15) {
                            if let profilePicture = user.profilePicture,
                               let url = URL(string: profilePicture) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .foregroundColor(.gray)
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.gray)
                            }
                            
                            Text(user.username ?? "User")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let bio = user.bio {
                                Text(bio)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Sign Out Button
                        Button(action: {
                            authManager.signOut()
                        }) {
                            Text("Sign Out")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 50)
                    } else {
                        Text("Loading user data...")
                            .foregroundColor(.secondary)
                    }
                }
                .navigationTitle("Kick")
                #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
            }
        }
    }
}

#Preview {
    HomeView(authManager: AuthenticationManager())
}

