//
//  InfoTip.swift
//  MyAnimeList
//
//  Created by Samuel He on 2025/5/18.
//

import SwiftUI

struct InfoTip: View {
    @State private var showTip = false
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    var width: CGFloat?
    var height: CGFloat?
    var iconFont: Font?


    var body: some View {
        Button(action: {
            showTip.toggle()
        }) {
            Image(systemName: "info.circle")
                .font(iconFont)
        }
        .popover(isPresented: $showTip) {
            VStack {
                Text(title)
                    .font(.callout)
                    .bold()
                    .foregroundStyle(.blue)
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width, height: height)
            .padding()
            .presentationCompactAdaptation(.popover)
        }
    }
}
