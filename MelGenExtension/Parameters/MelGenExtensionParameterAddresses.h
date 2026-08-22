//
//  MelGenExtensionParameterAddresses.h
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

#pragma once

#include <AudioToolbox/AUParameters.h>

typedef NS_ENUM(AUParameterAddress, MelGenExtensionParameterAddress) {
    sendNote = 0,
    midiNoteNumber = 1
};
