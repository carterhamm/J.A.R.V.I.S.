//
//  SwiftUIView.swift
//  JARVIS
//
//  Created by Carter Hammond on 6/25/25.
//

import SwiftUI

struct SwiftUIView: View {
    @State private var gearRotation: Double = 0
    @State private var isSmileyTapped: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.blue.opacity(0.3)
                .ignoresSafeArea()

            Image(systemName: "gearshape.fill")
                .font(.largeTitle)
                .padding(20)
                .rotationEffect(.degrees(gearRotation))
                .onAppear {
                    withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                        gearRotation = 360
                    }
                }

            Image(systemName: "smiley")
                .font(.system(size: 100))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .scaleEffect(isSmileyTapped ? 1.5 : 1.0)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isSmileyTapped = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation(.easeIn(duration: 0.25)) {
                            isSmileyTapped = false
                        }
                    }
                }
        }
    }
}

#Preview {
    SwiftUIView()
}
