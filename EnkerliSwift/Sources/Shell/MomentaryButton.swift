//
//  MomentaryButton.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import SwiftUI

public struct MomentaryButton: View {
    public let normalColor = Color(red: 51.0 / 255.0, green: 51.0 / 255.0, blue: 51.0 / 255.0)
    public let activeColor = Color(red: 50.0 / 255.0, green: 103.0 / 255.0, blue: 222.0 / 255.0)
    
    public init(_ text: String, param: ObservableAUParameter) {
        self.text = text
        self.param = param
    }
    
    public var text: String
    
    /// The value that this button should bind to
    ///
    /// The paramter value is treated as a bool, with 0.0 and 1.0  mapping to false and true, respectively
    @State public var param: ObservableAUParameter
    
    public var value: Bool {
        get {
            param.value != 0
        }
        nonmutating set {
            param.value = newValue ? 1.0 : 0.0
        }
    }
    
    public var body: some View {
        Text("\(text)")
            .padding()
            .background {
                value ? activeColor : normalColor
            }
            .cornerRadius(9.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged({ _ in
                        if !value {
                            value = true
                        }
                    })
                    .onEnded({ _ in
                        value = false
                    })
            )
    }
}
