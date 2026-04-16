//
//  LoudnessMatchView.swift
//  Tinnitus Capstone
//

import SwiftUI

struct LoudnessMatchView: View {
    @State private var loudness: Double = 0.3   // start at a moderate level
    
    // how much the arrows change loudness (smaller = finer control)
    private let arrowStep: Double = 0.02        // 2% change per tap
    
    // For going back to HomeView
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                
                // Top menu + title (NOW TAPPABLE TO GO BACK)
                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        dismiss()   // go back to HomeView
                    } label: {
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .font(.title3)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.top)
                            
                            Text("LOUDNESS MATCHING")
                                .font(.system(size: 24, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        // make the whole top area clickable, not just the text/icon
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain) // keeps original look, no button styling
                    
                    Spacer()
                }
                
                // Vertical slider
                Slider(value: $loudness, in: 0...1)
                    .rotationEffect(.degrees(-90))
                    .frame(height: 320)
                    .position(
                        x: geo.size.width / 5,
                        y: geo.size.height / 2
                    )
                
                // Up / Down arrows
                VStack(spacing: 40) {
                    Button {
                        loudness = min(loudness + arrowStep, 1.0)
                    } label: {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }

                    Button {
                        loudness = max(loudness - arrowStep, 0.0)
                    } label: {
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                            .rotationEffect(.degrees(180))
                    }
                }
                .position(
                    x: geo.size.width * 0.6,
                    y: geo.size.height / 2
                )
                
                // Match button
                Button {
                    // here you could store the matched value
                } label: {
                    Text("MATCH")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .position(
                    x: geo.size.width * 0.6,
                    y: geo.size.height / 2 + 150
                )
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            // start the tone and set initial volume
            ToneGenerator.shared.start()
            ToneGenerator.shared.setVolume(loudness)
        }
        .onDisappear {
            ToneGenerator.shared.stop()
        }
        .onChange(of: loudness) { newValue in
            // louder at the top, quieter at the bottom
            ToneGenerator.shared.setVolume(newValue)
        }
    }
}

#Preview {
    LoudnessMatchView()
}
