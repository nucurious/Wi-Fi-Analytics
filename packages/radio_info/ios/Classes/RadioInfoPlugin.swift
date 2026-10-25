import CoreTelephony
import Flutter
import Network
import NetworkExtension
import UIKit
import os

/// iOS only exposes the radio technology type (LTE, 5G NSA, 5G SA, ...).
/// Signal metrics such as RSRP/SINR are not available to third-party apps.
public class RadioInfoPlugin: NSObject, FlutterPlugin {
    private let telephony = CTTelephonyNetworkInfo()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "wifi_analytics.radio_info.path")
    private var currentPath: NWPath?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "wifi_analytics/radio_info",
            binaryMessenger: registrar.messenger())
        let instance = RadioInfoPlugin()
        UIDevice.current.isBatteryMonitoringEnabled = true
        instance.startPathMonitor()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        monitor.start(queue: monitorQueue)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getRadioInfo":
            let base = collect()
            if (base["connection"] as? String) == "WIFI", #available(iOS 14.0, *) {
                // Needs the Access WiFi Information capability and location permission; otherwise the name stays blank.
                NEHotspotNetwork.fetchCurrent { net in
                    var out = base
                    if let net = net {
                        out["wifiSsid"] = net.ssid
                        out["wifiBssid"] = net.bssid
                    }
                    DispatchQueue.main.async { result(out) }
                }
            } else {
                result(base)
            }
        case "getHealth":
            result(health())
        case "getDeviceInfo":
            // iOS never exposes the IMEI to apps; the tester enters it in Settings.
            var sys = utsname()
            uname(&sys)
            let machine = withUnsafePointer(to: &sys.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
            result(["make": "Apple", "model": machine.replacingOccurrences(of: ",", with: "-"), "osVersion": "iOS " + UIDevice.current.systemVersion,
                    "buildIncremental": UIDevice.current.systemVersion])
        case "hasPhonePermission", "requestPhonePermission":
            result(true)  // No permission needed on iOS.
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func collect() -> [String: Any] {
        var info: [String: Any] = ["platform": "ios"]

        var path: NWPath?
        monitorQueue.sync { path = currentPath }
        if let path = path {
            info["internetValidated"] = path.status == .satisfied
            if path.status != .satisfied {
                info["connection"] = "NONE"
            } else if path.usesInterfaceType(.wifi) {
                info["connection"] = "WIFI"
            } else if path.usesInterfaceType(.cellular) {
                info["connection"] = "CELLULAR"
            } else if path.usesInterfaceType(.wiredEthernet) {
                info["connection"] = "ETHERNET"
            } else {
                info["connection"] = "OTHER"
            }
        } else {
            info["connection"] = "UNKNOWN"
        }

        var tech: String?
        let techs = telephony.serviceCurrentRadioAccessTechnology ?? [:]
        if #available(iOS 13.0, *) {
            if let id = telephony.dataServiceIdentifier {
                tech = techs[id]
            }
        }
        if tech == nil {
            tech = techs.values.first
        }

        if let t = tech {
            info["dataNetworkType"] = shortName(t)
            info["rat"] = ratLabel(t)
        } else {
            info["rat"] = "No service"
        }
        return info
    }

    /// Phone health for the Analytics Pro health log (same keys as Android; values iOS does not give are left out).
    private func health() -> [String: Any] {
        var h: [String: Any] = [:]
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        if dev.batteryLevel >= 0 { h["batteryPct"] = Double(dev.batteryLevel) * 100.0 }
        switch dev.batteryState {
        case .charging: h["batteryStatus"] = 2
        case .full: h["batteryStatus"] = 5
        case .unplugged: h["batteryStatus"] = 3
        default: h["batteryStatus"] = 1
        }
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: h["thermalStatus"] = 0
        case .fair: h["thermalStatus"] = 1
        case .serious: h["thermalStatus"] = 3
        case .critical: h["thermalStatus"] = 4
        @unknown default: h["thermalStatus"] = 0
        }
        h["powerSave"] = ProcessInfo.processInfo.isLowPowerModeEnabled  // Low Power Mode
        h["screenOn"] = UIApplication.shared.applicationState == .active  // app in front
        let avail = Double(os_proc_available_memory()) / 1_048_576.0  // memory this app can still use before iOS ends it
        h["availMemMb"] = avail
        h["lowMemory"] = avail < 150.0
        if let mb = footprintMb() { h["appPssMb"] = mb }
        return h
    }

    private func footprintMb() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576.0 : nil
    }

    private func shortName(_ t: String) -> String {
        return t.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
    }

    private func ratLabel(_ t: String) -> String {
        let s = shortName(t)
        switch s {
        case "NRNSA": return "5G NSA"
        case "NR": return "5G SA"
        case "LTE": return "LTE"
        case "WCDMA", "HSDPA", "HSUPA", "eHRPD", "CDMAEVDORev0", "CDMAEVDORevA", "CDMAEVDORevB":
            return "3G"
        case "GPRS", "Edge", "CDMA1x":
            return "2G"
        default:
            return s
        }
    }
}
