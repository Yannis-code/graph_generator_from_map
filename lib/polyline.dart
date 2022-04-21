import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class PolylineZ extends Polyline {
  final List<List<dynamic>> pointsZ;
  final List<Offset> offsets = [];
  final double strokeWidth;
  final Color color;
  final double borderStrokeWidth;
  final Color? borderColor;
  final List<Color>? gradientColors;
  final List<double>? colorsStop;
  final bool isDotted;
  late final LatLngBounds boundingBox;

  PolylineZ({
    required this.pointsZ,
    this.strokeWidth = 1.0,
    this.color = const Color(0xFF00FF00),
    this.borderStrokeWidth = 0.0,
    this.borderColor = const Color(0xFFFFFF00),
    this.gradientColors,
    this.colorsStop,
    this.isDotted = false,
  }) : super(
          points: pointsZ.map<LatLng>((e) {
            return e[0];
          }).toList(),
          strokeWidth: strokeWidth,
          color: color,
          borderStrokeWidth: borderStrokeWidth,
          borderColor: borderColor,
          gradientColors: gradientColors,
          colorsStop: colorsStop,
          isDotted: isDotted,
        );

  @override
  bool operator ==(Object other) {
    if (this != other || other.runtimeType != runtimeType) {
      return false;
    }
    other as PolylineZ;
    for (var i = 0; i < pointsZ.length; i++) {
      if (pointsZ[i][0] != other.pointsZ[i][0] ||
          pointsZ[i][1] != other.pointsZ[i][1]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode =>
      super.hashCode + pointsZ.first.hashCode + pointsZ.last[1].hashCode;
}
