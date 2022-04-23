import 'dart:math';
import 'package:latlong2/latlong.dart';

double degreesToRadians(double degrees) {
  return degrees * pi / 180;
}

double dist(LatLng latLong1, LatLng latLong2) {
  double earthRadiusKm = 6371;
  double latDif = degreesToRadians(latLong2.latitude - latLong1.latitude);
  double lonDif = degreesToRadians(latLong2.longitude - latLong1.longitude);

  double lat1 = degreesToRadians(latLong1.latitude);
  double lat2 = degreesToRadians(latLong2.latitude);

  double a = sin(latDif / 2) * sin(latDif / 2) +
      cos(lat1) * cos(lat2) * sin(lonDif / 2) * sin(lonDif / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusKm * c;
}

dynamic getClosestMarkers(LatLng latLng, List<dynamic> markers) {
  dynamic closest = markers[0];
  for (var mark in markers) {
    if (dist(latLng, mark["marker"].point) <
        dist(latLng, closest["marker"].point)) {
      closest = mark;
    }
  }
  return closest;
}

dynamic getClosestStairsSup(LatLng latLng, List<dynamic> markers) {
  dynamic closest = markers.firstWhere((e) => e["options"]["type"] == "stairs",
      orElse: () => []);
  for (var mark in markers) {
    if (mark["options"]["type"] == "stairs" &&
        dist(latLng, mark["marker"].point) <
            dist(latLng, closest["marker"].point)) {
      closest = mark;
    }
  }
  return closest;
}
