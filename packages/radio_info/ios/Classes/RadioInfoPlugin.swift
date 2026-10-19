import CoreTelephony
import Flutter
import Network
import UIKit

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
            result(collect())
        case "getDeviceInfo":
            // iOS never exposes the IMEI to apps; the tester enters it in Settings.
            var sys = utsname()
            uname(&sys)
            let machine = withUnsafePointer(to: &sys.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
            }
            result(["make": "Apple", "model": machine, "osVersion": "iOS " + UIDevice.current.systemVersion,
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
