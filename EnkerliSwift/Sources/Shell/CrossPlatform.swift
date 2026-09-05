//
//  CrossPlatform.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import Foundation
import SwiftUI

#if os(iOS) || os(visionOS)
public typealias HostingController = UIHostingController
#elseif os(macOS)
public typealias HostingController = NSHostingController

extension NSView {
	
	public func bringSubviewToFront(_ view: NSView) {
		// This function is a no-opp for macOS
	}
}
#endif
