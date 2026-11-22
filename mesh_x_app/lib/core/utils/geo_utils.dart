import 'dart:math';

/// Utility methods for offline GPS coordinates, distance, and bearing computations.
class GeoUtils {
  static const double earthRadiusMeters = 6371000.0;

  /// Haversine formula to compute great-circle distance between two GPS coordinates in meters.
  static double computeDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Computes initial bearing (forward azimuth) from point 1 to point 2 in degrees (0..360).
  static double computeBearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final lat1Rad = _toRadians(lat1);
    final lat2Rad = _toRadians(lat2);
    final dLonRad = _toRadians(lon2 - lon1);

    final y = sin(dLonRad) * cos(lat2Rad);
    final x = cos(lat1Rad) * sin(lat2Rad) -
        sin(lat1Rad) * cos(lat2Rad) * cos(dLonRad);

    final initialBearingRad = atan2(y, x);
    final initialBearingDeg = _toDegrees(initialBearingRad);
    return (initialBearingDeg + 360) % 360;
  }

  /// Formats distance into a clean string (e.g. "420 m" or "3.8 km").
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  /// Estimates approximate distance from LoRa RSSI using Log-Distance Path Loss Model.
  /// n: path loss exponent (2.0 for free space, 2.7 to 3.5 for suburban/outdoor mesh).
  static double estimateDistanceMetersFromRssi(
    int rssi, {
    int measuredPowerAt1m = -42,
    double pathLossExponent = 2.8,
  }) {
    if (rssi >= 0) return 1.0;
    final ratio = (measuredPowerAt1m - rssi) / (10 * pathLossExponent);
    final dist = pow(10, ratio).toDouble();
    return dist.clamp(1.0, 50000.0);
  }

  static double _toRadians(double degrees) => degrees * (pi / 180.0);
  static double _toDegrees(double radians) => radians * (180.0 / pi);
}
