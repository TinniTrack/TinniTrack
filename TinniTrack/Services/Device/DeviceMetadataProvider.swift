import Foundation
import UIKit

protocol DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue]
    func outputDeviceInfo(for route: AudioOutputRoute?) -> [String: JSONValue]
}

struct SystemDeviceMetadataProvider: DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue] {
        [
            "model": .string(UIDevice.current.model),
            "system_name": .string(UIDevice.current.systemName),
            "system_version": .string(UIDevice.current.systemVersion)
        ]
    }

    func outputDeviceInfo(for route: AudioOutputRoute?) -> [String: JSONValue] {
        [
            "route_name": .string(route?.name ?? ""),
            "route_port_type": .string(route?.portType ?? ""),
            "route_gate": .string("study-no-1-airpods-pro-2-3-route-name-gate"),
            "route_gate_supported_generations": .array([
                .string("AirPods Pro 2"),
                .string("AirPods Pro 3")
            ])
        ]
    }
}
