//
//  Parameters.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import Foundation
import AudioToolbox
import Shell
import Kernel

let MelGenExtensionParameterSpecs = ParameterTreeSpec {
    ParameterGroupSpec(identifier: "global", name: "Global") {
        ParameterSpec(
            address: .playMelody,
            identifier: "playMelody",
            name: "Play",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )

        ParameterSpec(
            address: .playbackDirection,
            identifier: "playbackDirection",
            name: "Playback Direction",
            units: .indexed,
            valueRange: 0...2,
            defaultValue: AUValue(PluginPlaybackDirection.forward.rawValue),
            valueStrings: ["Forward", "Backward", "Ping-Pong"]
        )

        ParameterSpec(
            address: .hostSync,
            identifier: "hostSync",
            name: "Sync to Host",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )
    }
}

extension ParameterSpec {
    init(
        address: PluginParameterAddress,
        identifier: String,
        name: String,
        units: AudioUnitParameterUnit,
        valueRange: ClosedRange<AUValue>,
        defaultValue: AUValue,
        unitName: String? = nil,
        flags: AudioUnitParameterOptions = [AudioUnitParameterOptions.flag_IsWritable, AudioUnitParameterOptions.flag_IsReadable],
        valueStrings: [String]? = nil,
        dependentParameters: [NSNumber]? = nil
    ) {
        self.init(address: address.rawValue,
                  identifier: identifier,
                  name: name,
                  units: units,
                  valueRange: valueRange,
                  defaultValue: defaultValue,
                  unitName: unitName,
                  flags: flags,
                  valueStrings: valueStrings,
                  dependentParameters: dependentParameters)
    }
}
