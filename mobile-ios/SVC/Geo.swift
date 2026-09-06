import CoreLocation

/// E7: majlisga ulanishda oxirgi ma'lum GPS nuqtasi yuboriladi (best-effort).
/// Ruxsat berilmasa — `nil`, ulanish baribir davom etadi (Android bilan bir xil xulq).
final class GeoProvider: NSObject, CLLocationManagerDelegate {
    static let shared = GeoProvider()

    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Ruxsat so'raladi (birinchi marta) va joriy nuqta qaytariladi.
    func request() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func current() -> GeoPoint? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let loc = manager.location
        else { return nil }

        return GeoPoint(
            lat: loc.coordinate.latitude,
            lon: loc.coordinate.longitude,
            accuracy: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
