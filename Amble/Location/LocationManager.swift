import Foundation
import CoreLocation
import Observation

@Observable
@MainActor
final class LocationManager: NSObject {
    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        authorizationStatus = manager.authorizationStatus
    }

    /// True once the user has granted When-In-Use (or legacy Always).
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// True once the user has made any choice (authorized, denied, or restricted).
    /// Used by UI to flip from "Share my location" to "Continue".
    var isDetermined: Bool {
        authorizationStatus != .notDetermined
    }

    /// Presents the iOS When-In-Use dialog if the user hasn't decided yet, and
    /// awaits the result so onboarding can advance cleanly after the dialog
    /// dismisses. No-ops if the user has already chosen.
    @discardableResult
    func requestAuthorization() async -> CLAuthorizationStatus {
        if authorizationStatus != .notDetermined {
            return authorizationStatus
        }
        return await withCheckedContinuation { cont in
            authContinuation = cont
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Fire-and-forget variant, kept for call sites that don't need to await.
    func requestAuthorizationIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Resolves one-shot location. Returns `nil` immediately if the user
    /// hasn't authorized us — importantly, this does NOT trigger the iOS
    /// permission dialog. SOS in particular must never surface a modal
    /// during an emergency; we prime permission earlier, in onboarding.
    func requestLocation() async -> CLLocation? {
        guard isAuthorized else { return nil }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    /// Apple Maps URL that iMessage renders as a rich preview card AND,
    /// crucially, opens in Apple Maps as a proper pinned location with a
    /// prominent Directions button. The `q=lat,lon` form is what unlocks
    /// the pin + action card — a plain `ll=` URL only centers the map
    /// without dropping a pin, which left earlier receivers unable to
    /// actually navigate to the senior.
    static func mapsLink(for loc: CLLocation) -> String {
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        return "https://maps.apple.com/?q=\(lat),\(lon)"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            lastLocation = last
            continuation?.resume(returning: last)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            // Resume a pending auth request once the user has actually chosen.
            if status != .notDetermined, let cont = authContinuation {
                authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }
}
