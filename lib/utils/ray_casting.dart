import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RayCasting {
  static bool isInsidePolygons(List<Polygon> polygons, LatLng currPos) {
    for (var poly in polygons) {
      int count = 0;
      double x = currPos.latitude;
      double y = currPos.longitude;

      for (var i = 0; i < poly.points.length - 1; i++) {
        double x1 = poly.points[i].latitude;
        double y1 = poly.points[i].longitude;
        double x2 = poly.points[i + 1].latitude;
        double y2 = poly.points[i + 1].longitude;

        if (y < y1 != y < y2 && x < (x2 - x1) * (y - y1) / (y2 - y1) + x1) {
          count++;
        }
      }
      if (count % 2 == 1) {
        return true;
      }
    }
    return false;
  }
}
