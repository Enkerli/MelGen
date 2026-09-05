//
//  PluginViewController.swift
//  MelGenExtension
//
//  The AUv3 view-controller host, with the two app-specific lines lifted out.
//
//  It was `AudioUnitViewController` and it named `MelGenExtensionMainView`
//  directly — PORTING.md's `AudioUnitViewController → MelGenExtensionMainView`
//  seam. Everything here is the same lifecycle every AUv3 in this suite needs:
//  create the audio unit on the main queue, set up the parameter tree before
//  building the `@AUParameterUI` properties, then host a SwiftUI view and pin it
//  to the bounds. The two things that differ per plug-in are which audio unit
//  and which root view, so they are the two overrides below.
//
//  A generic parameter was the shape §3 predicted. It cannot be one: the
//  principal class is looked up by name out of Info.plist through the ObjC
//  runtime, and a generic Swift class has no ObjC name and cannot override the
//  `@objc` members `AUViewController` declares. A base class and two overrides
//  is the shape that survives that constraint, and it is the boring one.
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import Combine
import CoreAudioKit
import os
import SwiftUI

private let log = Logger(subsystem: "com.enkerli.MelGenExtension", category: "AudioUnitViewController")

@MainActor
open class PluginViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: AUAudioUnit?

    var hostingController: HostingController<AnyView>?

    // MARK: - What a plug-in supplies
    //
    // Internal rather than `open`: everything is one module today, so `open`
    // buys nothing and `makeRootView` cannot be public while
    // `ObservableAUParameterGroup` is internal. When the foundation becomes a
    // package these three become `open` and that type becomes public — an
    // access-level sweep the whole foundation needs at once, not three files.

    /// The audio unit this plug-in is. Subclasses return their own
    /// `PluginAudioUnit`; the shell does the rest of the factory dance around it.
    func makeAudioUnit(componentDescription: AudioComponentDescription) throws -> PluginAudioUnit {
        try PluginAudioUnit(componentDescription: componentDescription, options: [])
    }

    /// The root view. Type-erased rather than generic for the reason in the file
    /// comment: one `AnyView` at the very top of a plug-in's view tree costs a
    /// box per rebuild of the root and nothing else, and it is the price of the
    /// principal class staying visible to the ObjC runtime.
    func makeRootView(parameterTree: ObservableAUParameterGroup,
                           audioUnit: PluginAudioUnit) -> AnyView {
        AnyView(EmptyView())
    }
    
    /// The parameters the host sees. `MelGenExtensionParameterSpecs` lives in
    /// `Parameters/`, which this check reads as shell because of where it sits —
    /// but the parameters of a plug-in are the plug-in's, so it is an override
    /// rather than a call. A sibling with a different set of knobs supplies them
    /// here and changes nothing else.
    var parameterTreeSpec: ParameterTreeSpec { ParameterTreeSpec {} }
    
    private var observation: NSKeyValueObservation?

	/* iOS View lifcycle
	public override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)

		// Recreate any view related resources here..
	}

	public override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)

		// Destroy any view related content here..
	}
	*/

	/* macOS View lifcycle
	public override func viewWillAppear() {
		super.viewWillAppear()
		
		// Recreate any view related resources here..
	}

	public override func viewDidDisappear() {
		super.viewDidDisappear()

		// Destroy any view related content here..
	}
	*/

	deinit {
	}

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Accessing the `audioUnit` parameter prompts the AU to be created via createAudioUnit(with:)
        guard let audioUnit = self.audioUnit else {
            return
        }
        configureSwiftUIView(audioUnit: audioUnit)
    }
    
	nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
		return try DispatchQueue.main.sync {
			
			audioUnit = try makeAudioUnit(componentDescription: componentDescription)

			guard let audioUnit = self.audioUnit as? PluginAudioUnit else {
				log.error("Unable to create the plug-in's audio unit")
				return audioUnit!
			}
			
			defer {
				// Configure the SwiftUI view after creating the AU, instead of in viewDidLoad,
				// so that the parameter tree is set up before we build our @AUParameterUI properties
				DispatchQueue.main.async {
					self.configureSwiftUIView(audioUnit: audioUnit)
				}
			}
			
			audioUnit.setupParameterTree(parameterTreeSpec.createAUParameterTree())
			
			self.observation = audioUnit.observe(\.allParameterValues, options: [.new]) { object, change in
				guard let tree = audioUnit.parameterTree else { return }
				
				// This insures the Audio Unit gets initial values from the host.
				for param in tree.allParameters { param.value = param.value }
			}
			
			guard audioUnit.parameterTree != nil else {
				log.error("Unable to access AU ParameterTree")
				return audioUnit
			}
			
			return audioUnit
		}
	}
    
    private func configureSwiftUIView(audioUnit: AUAudioUnit) {
        if let host = hostingController {
            host.removeFromParent()
            host.view.removeFromSuperview()
        }
        
        guard let observableParameterTree = audioUnit.observableParameterTree,
              let audioUnit = audioUnit as? PluginAudioUnit else {
            return
        }
        let content = makeRootView(parameterTree: observableParameterTree,
                                   audioUnit: audioUnit)
        let host = HostingController(rootView: content)
        self.addChild(host)
        host.view.frame = self.view.bounds
        self.view.addSubview(host.view)
        hostingController = host
        
        // Make sure the SwiftUI view fills the full area provided by the view controller
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        host.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        host.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        host.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
        self.view.bringSubviewToFront(host.view)
    }
    
}
