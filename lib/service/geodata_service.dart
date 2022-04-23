// ignore_for_file: file_names

import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GeoJson {
  static Future<List<Polygon>> buildPolygons() async {
    // Chargement du fichier contenant les informations sur les polygones
    final String response =
        await rootBundle.loadString('assets/buildingData.geoJSON');
    final data = await json.decode(response);
    List<Polygon> polygons = [];

    // Lecture des propriétés de chaque polygon du fichier
    for (var feature in data["features"]) {
      List<LatLng> _points = [];
      List<List<LatLng>> _holePoints = [];

      for (var i = 0; i < feature["geometry"]["coordinates"].length; i++) {
        // Création de la liste de sommets du polygone
        if (i == 0) {
          for (var point in feature["geometry"]["coordinates"][i]) {
            _points.add(LatLng(point[1], point[0]));
          }
        }
        // Création de la liste de sommets correspondants aux éventuels trous à l'intérieur du polygone
        else {
          List<LatLng> _holes = [];
          for (var point in feature["geometry"]["coordinates"][i]) {
            _holes.add(LatLng(point[1], point[0]));
          }
          _holePoints.add(_holes);
        }
      }

      // Création du polygon avec les listes de points précèdemment créées
      var polygon = Polygon(
        points: _points,
        holePointsList: _holePoints,
        color: Color(int.parse(feature["properties"]["fill"].substring(1, 7),
                radix: 16) +
            0xFF000000),
        borderColor: Color(int.parse(
                feature["properties"]["stroke"].substring(1, 7),
                radix: 16) +
            0xFF000000),
        borderStrokeWidth: feature["properties"]["stroke-width"],
      );
      polygons.add(polygon);
    }

    return polygons;
  }
}