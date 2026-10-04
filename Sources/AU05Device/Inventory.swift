import Foundation
import IOKit.hid

public struct HIDInterfaceInfo: Codable, Sendable {
    public struct Element: Codable, Hashable, Sendable {
        public let usagePage: Int
        public let usage: Int
        public let minimum: Int
        public let maximum: Int
        public let relative: Bool
    }
    public let product: String
    public let vendorID: Int
    public let productID: Int
    public let usagePage: Int
    public let usage: Int
    public let inputs: [Element]
}
public enum HIDInventory {
    /// Reads descriptors only. Never seizes an interface or subscribes to keys.
    public static func interfaces() -> [HIDInterfaceInfo] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        IOHIDManagerSetDeviceMatching(manager, nil)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return [] }
        defer { IOHIDManagerClose(manager, 0) }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        return devices.map { device in
            func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
            let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] ?? []
            let inputs = Set(elements.compactMap { element -> HIDInterfaceInfo.Element? in
                let type = IOHIDElementGetType(element)
                guard type == kIOHIDElementTypeInput_Misc || type == kIOHIDElementTypeInput_Button ||
                      type == kIOHIDElementTypeInput_Axis || type == kIOHIDElementTypeInput_ScanCodes else { return nil }
                return HIDInterfaceInfo.Element(usagePage: Int(IOHIDElementGetUsagePage(element)),
                    usage: Int(IOHIDElementGetUsage(element)), minimum: IOHIDElementGetLogicalMin(element),
                    maximum: IOHIDElementGetLogicalMax(element), relative: IOHIDElementIsRelative(element))
            }).sorted { ($0.usagePage, $0.usage) < ($1.usagePage, $1.usage) }
            return HIDInterfaceInfo(product: IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "HID",
                vendorID: number(kIOHIDVendorIDKey), productID: number(kIOHIDProductIDKey),
                usagePage: number(kIOHIDPrimaryUsagePageKey), usage: number(kIOHIDPrimaryUsageKey), inputs: inputs)
        }.sorted { ($0.vendorID, $0.productID, $0.usagePage, $0.usage) < ($1.vendorID, $1.productID, $1.usagePage, $1.usage) }
    }
}
