//
//  ParameterSpecBase.swift
//  MelGenExtension
//
//  Created by Alexandre Enkerli on 2026-08-21.
//

import Foundation
import AudioToolbox

public protocol NodeSpec: Sendable {}

extension NodeSpec {
    public static func validateID(_ name: String) -> String {
        let msg = "Parameter identifier should: not be empty, begin with a letter, and only contain alpha numeric characters or underscores. Hint: Use camelCase."
        assert(name.isAlphanumeric(), msg)
        return name
    }
}

@resultBuilder public struct ParameterGroupBuilder {
    public static func buildBlock() -> [NodeSpec] { [] }
    public static func buildBlock(_ nodes: NodeSpec...) -> [NodeSpec] { nodes }
}

/// Specification for a group of parameters.
public struct ParameterGroupSpec: NodeSpec {
    public let identifier: String
    public let name: String
    public let children: [NodeSpec]

    public init(identifier: String, name: String, @ParameterGroupBuilder _ children: () -> [NodeSpec]) {
        self.identifier = ParameterGroupSpec.validateID(identifier)
        self.name = name
        self.children = children()
    }
}

public struct ParameterTreeSpec: NodeSpec {
    public let children: [NodeSpec]
    public init(@ParameterGroupBuilder _ children: () -> [NodeSpec]) { self.children = children() }
}

/// ParameterSpec mirrors what gets passed to
/// AUParameterTree.createParameter, but also provides a default value
public struct ParameterSpec: NodeSpec {
    public let identifier: String
    public let name: String
    public let address: AUParameterAddress
    public let minValue: AUValue
    public let maxValue: AUValue
    public let defaultValue: AUValue
    public let units: AudioUnitParameterUnit
    public let unitName: String?
    public let flags: AudioUnitParameterOptions
    public let valueStrings: [String]?
    public let dependentParameters: [NSNumber]?

    /// Init a new parameter spec
    /// - Parameters:
    ///   - address: A unique AUParameterAddress (Integer) which represents the parameter
    ///   - identifier: A unique String which is used to access the parameter
    ///   - name: The localized display name of the parameter
    ///   - units: The parameters unit of measurement
    ///   - valueRange: The parameters range in above units
    ///   - defaultValue: The default value of the parameter
    ///   - unitName: The name of the units of measurement
    ///   - flags: A set of the parameters options
    ///   - valueStrings: String representation of each value
    ///   - dependentParameters: The addresses of dependant parameters
    public init(
        address: AUParameterAddress,
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
        self.identifier = ParameterSpec.validateID(identifier)
        self.name = name
        self.address = address
        self.minValue = valueRange.lowerBound
        self.maxValue = valueRange.upperBound
        self.defaultValue = defaultValue
        self.units = units
        self.unitName = unitName
        self.flags = flags
        self.valueStrings = valueStrings
        self.dependentParameters = dependentParameters
    }
}

// MARK: - Tree factory for parameter spec

extension AUParameterTree {

    public class func createNode(from spec: NodeSpec) -> AUParameterNode {
        switch spec {
        case let parameterSpec as ParameterSpec:
            return AUParameterTree.createParameter(from: parameterSpec)
        case let groupSpec as ParameterGroupSpec:
            return AUParameterTree.createParameterGroup(from: groupSpec)
        default:
            return AUParameterNode()
        }
    }

    public class func createParameterGroup(from spec: ParameterGroupSpec) -> AUParameterGroup {
        return self.createGroup(
            withIdentifier: spec.identifier,
            name: spec.name,
            children: spec.children.createAUParameterNodes()
        )
    }

    public class func createParameter(from spec: ParameterSpec) -> AUParameter {
        let param = self.createParameter(
            withIdentifier: spec.identifier,
            name: spec.name,
            address: spec.address,
            min: spec.minValue,
            max: spec.maxValue,
            unit: spec.units,
            unitName: spec.unitName,
            flags: spec.flags,
            valueStrings: spec.valueStrings,
            dependentParameters: spec.dependentParameters
        )
        param.value = spec.defaultValue
        return param
    }
}

extension Array where Element == NodeSpec {
    public func createAUParameterNodes() -> [AUParameterNode] {
        self.map { spec in
            AUParameterTree.createNode(from: spec)
        }
    }

    public func createAUParameterTree() -> AUParameterTree {
        AUParameterTree.createTree(withChildren: self.createAUParameterNodes())
    }
}

extension ParameterTreeSpec {
    public func createAUParameterTree() -> AUParameterTree {
        AUParameterTree.createTree(withChildren: self.children.createAUParameterNodes())
    }
}
