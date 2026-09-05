//
//  PluginParameterAddresses.h
//  Kernel
//
//  The parameters this kernel has.
//
//  It was PluginParameterAddresses.h, which made the kernel look as if
//  it depended on MelGen — the one seam PORTING.md's boundary check could never
//  see, because everything under Common/, DSP/ and Parameters/ is classified
//  shell by its directory rather than by what it names. The dependency was in
//  the name. Play, direction and host sync are what a loop player has; a
//  sibling plug-in with its own knobs adds them to its own parameter tree and
//  leaves these three alone.
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

#pragma once

#include <AudioToolbox/AUParameters.h>

// Addresses 0 and 1 held the old MIDI test note (sendNote, midiNoteNumber) and
// are deliberately left unused: reusing them would make automation saved in an
// existing host session drive an unrelated parameter.
typedef NS_ENUM(AUParameterAddress, PluginParameterAddress) {
    playMelody = 2,
    playbackDirection = 3,
    hostSync = 4
};

// Values of the playbackDirection parameter, matching DrawnQurve's
// PlaybackDirection so the two plug-ins agree on what each index means.
typedef NS_ENUM(int, PluginPlaybackDirection) {
    PluginPlaybackDirectionForward = 0,
    PluginPlaybackDirectionBackward = 1,
    PluginPlaybackDirectionPingPong = 2
};
