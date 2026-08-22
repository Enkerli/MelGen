//
//  TypeAliases.swift
//  MelGen
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import CoreMIDI
import AudioToolbox

#if os(iOS) || os(visionOS)
import UIKit

public typealias ViewController = UIViewController
#elseif os(macOS)
import AppKit

public typealias KitView = NSView
public typealias ViewController = NSViewController
#endif
