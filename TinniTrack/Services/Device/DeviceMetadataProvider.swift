import Foundation
import UIKit

protocol DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue]
}

struct SystemDeviceMetadataProvider: DeviceMetadataProviding {
    func currentDeviceInfo() -> [String: JSONValue] {
        [
            "model": .string(UIDevice.current.model),
            "system_name": .string(UIDevice.current.systemName),
            "system_version": .string(UIDevice.current.systemVersion)
        ]
    }
}
