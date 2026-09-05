//
//  AudioUnitViewController.swift
//  MelGenExtension
//
//  MelGen's principal class: the three things a plug-in tells the shell.
//
//  Info.plist names `$(PRODUCT_MODULE_NAME).AudioUnitViewController` as both the
//  principal class and the factory function, so this type keeps that name and
//  keeps being the entry point. Everything it used to do is in
//  `PluginViewController` now — see the note at the top of that file for why the
//  shape is a base class rather than the generic parameter PORTING.md §3
//  predicted.
//

import CoreAudioKit
import SwiftUI
import Shell

@MainActor
public final class AudioUnitViewController: PluginViewController {

    public override func makeAudioUnit(componentDescription: AudioComponentDescription) throws -> PluginAudioUnit {
        try MelGenExtensionAudioUnit(componentDescription: componentDescription, options: [])
    }

    public override var parameterTreeSpec: ParameterTreeSpec { MelGenExtensionParameterSpecs }

    public override func makeRootView(parameterTree: ObservableAUParameterGroup,
                                      audioUnit: PluginAudioUnit) -> AnyView {
        AnyView(MelGenExtensionMainView(parameterTree: parameterTree,
                                        audioUnit: audioUnit as? MelGenExtensionAudioUnit))
    }
}
