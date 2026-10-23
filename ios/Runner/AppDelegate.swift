import Flutter
import CoreLocation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let locationBridge = FieldLogLocationBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.fieldlog/location",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak bridge = self.locationBridge] call, result in
        guard let bridge else {
          result(FlutterError(code: "LOCATION_UNAVAILABLE", message: "Location service is unavailable", details: nil))
          return
        }
        bridge.handle(call, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class FieldLogLocationBridge: NSObject, CLLocationManagerDelegate {
  private let manager: CLLocationManager
  private var permissionResult: FlutterResult?
  private var locationResults: [FlutterResult] = []
  private var locationTimeout: DispatchWorkItem?

  override init() {
    manager = CLLocationManager()
    super.init()
    manager.delegate = self
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isLocationServiceEnabled":
      result(CLLocationManager.locationServicesEnabled())
    case "checkPermission":
      result(permissionStatus())
    case "requestPermission":
      requestPermission(result: result)
    case "getCurrentPosition":
      requestCurrentPosition(result: result)
    case "openLocationSettings", "openAppSettings":
      openAppSettings(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func authorizationStatus() -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return manager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  private func permissionStatus() -> String {
    switch authorizationStatus() {
    case .authorizedAlways, .authorizedWhenInUse:
      return "granted"
    case .denied, .restricted:
      return "deniedForever"
    case .notDetermined:
      return "denied"
    @unknown default:
      return "denied"
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    switch authorizationStatus() {
    case .notDetermined:
      guard permissionResult == nil else {
        result(FlutterError(code: "PERMISSION_REQUEST_IN_PROGRESS", message: "A location permission request is already active", details: nil))
        return
      }
      permissionResult = result
      manager.requestWhenInUseAuthorization()
    default:
      result(permissionStatus())
    }
  }

  private func requestCurrentPosition(result: @escaping FlutterResult) {
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(code: "LOCATION_DISABLED", message: "Location services are disabled", details: nil))
      return
    }
    guard permissionStatus() == "granted" else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "Location permission is not granted", details: nil))
      return
    }
    locationResults.append(result)
    guard locationResults.count == 1 else { return }

    manager.desiredAccuracy = kCLLocationAccuracyBest

    let timeout = DispatchWorkItem { [weak self] in
      self?.finishLocation(error: FlutterError(code: "LOCATION_TIMEOUT", message: "No location fix was available", details: nil))
    }
    locationTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    manager.requestLocation()
  }

  private func finishLocation(location: CLLocation? = nil, error: FlutterError? = nil) {
    guard !locationResults.isEmpty else { return }
    let pendingResults = locationResults
    locationResults.removeAll()
    locationTimeout?.cancel()
    locationTimeout = nil

    for result in pendingResults {
      if let error {
        result(error)
      } else if let location {
        result([
          "latitude": location.coordinate.latitude,
          "longitude": location.coordinate.longitude,
          "accuracy": location.horizontalAccuracy,
        ])
      } else {
        result(FlutterError(code: "LOCATION_UNAVAILABLE", message: "No location fix was available", details: nil))
      }
    }
  }

  private func openAppSettings(result: @escaping FlutterResult) {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(settingsURL, options: [:]) { opened in
      result(opened)
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    resolvePermissionRequest()
    if permissionStatus() != "granted", !locationResults.isEmpty {
      finishLocation(error: FlutterError(code: "PERMISSION_DENIED", message: "Location permission is not granted", details: nil))
    }
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    resolvePermissionRequest()
    if permissionStatus() != "granted", !locationResults.isEmpty {
      finishLocation(error: FlutterError(code: "PERMISSION_DENIED", message: "Location permission is not granted", details: nil))
    }
  }

  private func resolvePermissionRequest() {
    guard let result = permissionResult, authorizationStatus() != .notDetermined else { return }
    permissionResult = nil
    result(permissionStatus())
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
    finishLocation(location: location)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if let locationError = error as? CLError, locationError.code == .locationUnknown {
      // Core Location may report a transient miss before a fix is available.
      // Keep waiting until the same 10-second limit used on Android.
      return
    }
    finishLocation(error: FlutterError(code: "LOCATION_UNAVAILABLE", message: error.localizedDescription, details: nil))
  }
}
