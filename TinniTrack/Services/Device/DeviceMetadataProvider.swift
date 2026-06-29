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
            "route_port_type": .string(route?.portType ?? "")
        ]
    }
}
