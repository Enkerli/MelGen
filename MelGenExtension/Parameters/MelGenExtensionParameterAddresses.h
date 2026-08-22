//
//  MelGenExtensionParameterAddresses.h
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

#pragma once

#include <AudioToolbox/AUParameters.h>

// Addresses 0 and 1 held the old MIDI test note (sendNote, midiNoteNumber) and
// are deliberately left unused: reusing them would make automation saved in an
// existing host session drive an unrelated parameter.
typedef NS_ENUM(AUParameterAddress, MelGenExtensionParameterAddress) {
    playMelody = 2,
    playbackDirection = 3,
    hostSync = 4
};

// Values of the playbackDirection parameter, matching DrawnQurve's
// PlaybackDirection so the two plug-ins agree on what each index means.
typedef NS_ENUM(int, MelGenPlaybackDirection) {
    MelGenPlaybackDirectionForward = 0,
    MelGenPlaybackDirectionBackward = 1,
    MelGenPlaybackDirectionPingPong = 2
};
