//
//  MelGenExtensionMainView.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import SwiftUI

struct MelGenExtensionMainView: View {
    var parameterTree: ObservableAUParameterGroup
    
    var body: some View {
        VStack {
            ParameterSlider(param: parameterTree.global.midiNoteNumber)
                .padding()
            MomentaryButton(
                "Play note",
                param: parameterTree.global.sendNote
            )
        }
    }
}
