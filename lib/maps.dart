// Import des packages flutter classiques

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

// Import des packages dart utiles pour les usage d'une carte
//
// dart:collection -> Fonctions de hashage
// dart:convert    -> Conversion des fichiers locaux
// dart:async      -> StreamControl
import 'dart:collection';
import 'dart:convert';
import 'dart:async';

// Import des packages externes permettant de créer une carte
//
// package:flutter_map                 -> Affichage des tiles de la carte
// package:latlong2                    -> Dépendance de flutter_map pour la position geographique
// package:flutter_map_location_marker -> Affichage de la position de l'appareil
// package:flutter_map_marker_popup    -> Affichage de markers avec popup
// package:google_polyline_algorithm   -> Désencodage de polyline de guidage
// package:google_polyline_algorithm   -> Désencodage de polyline de guidage
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart';
import 'package:flutter_map_marker_popup/flutter_map_marker_popup.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_generator/file_manager.dart';

import 'package:provider/provider.dart';

class Carte extends StatefulWidget {
  final double startZoom;
  final List<dynamic> center;
  final List<dynamic> route;
  final bool enableLocation;
  final List<dynamic> targetedBuilding;

  const Carte(
      {Key? key,
      this.route = const <String>[],
      this.center = const <double>[45.7607081914812, 3.1137603281196453],
      this.startZoom = 18.25,
      this.enableLocation = true,
      this.targetedBuilding = const <double>[]})
      : super(key: key);

  @override
  _CarteState createState() => _CarteState();
}

// Classe de la map affichée
class _CarteState extends State<Carte> {
  // Déclaration des listes d'objet à afficher sur la map
  List<Polygon> _polygons = [];
  List<Marker> _markers = [];
  List<Marker> _endMarkers = [];
  List<Polyline> _polylines = [];
  String _action = "";

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

  LatLng getArrowPos(LatLng latLong1, LatLng latLong2) {
    double latDist = (latLong2.latitude - latLong1.latitude);
    double lonDist = (latLong2.longitude - latLong1.longitude);
    double endLat = latDist * 0.9 + latLong1.latitude;
    double endLon = lonDist * 0.9 + latLong1.longitude;
    return LatLng(endLat, endLon);
  }

  Future<void> loadJson() async {
    Map<dynamic, dynamic> load = await FileManager.loadFromFile();
    List<Marker> markers = [];
    List<Marker> endMarkers = [];
    List<Polyline> polylines = [];
    for (var key in load.keys) {
      key as String;
      List<String> keyVal = key.split(", ");
      LatLng loadedLatLng =
          LatLng(double.parse(keyVal[0]), double.parse(keyVal[1]));
      markers.add(makeMarker(loadedLatLng));
      for (var connected in load[key]) {
        List<String> connectedCoord = connected.split(", ");
        LatLng connectedLatLng = LatLng(
            double.parse(connectedCoord[0]), double.parse(connectedCoord[1]));
        markers.add(makeMarker(loadedLatLng));
        Polyline poly = Polyline(
          points: [loadedLatLng, connectedLatLng],
          color: Colors.red,
          strokeWidth: 1.5,
        );
        Marker end = makeArrow(loadedLatLng, connectedLatLng);
        endMarkers.add(end);
        polylines.add(poly);
      }
    }
    setState(() {
      _markers = markers;
      _endMarkers = endMarkers;
      _polylines = polylines;
    });
  }

  void saveJson() {
    Map<String, dynamic> output = {};
    for (var poly in _polylines) {
      LatLng start = poly.points.first;
      LatLng end = poly.points.last;

      String startString = "${start.latitude}, ${start.longitude}";
      String endString = "${end.latitude}, ${end.longitude}";
      double distance = dist(start, end);

      String value = "${end.latitude}, ${end.longitude}, $distance";

      if (!output.containsKey(startString)) {
        output[startString] = [];
      }
      if (!output.containsKey(endString)) {
        output[endString] = [];
      }
      if (!output[startString].contains(value)) {
        output[startString].add(value);
      }
    }
    FileManager.writeToFile(output);
  }

  // Initialisation des state du widget
  @override
  void initState() {
    super.initState();
    //loadJson();
  }

  // Fermeture des Stream de control lorsque la Carte n'est plus affichée
  @override
  void dispose() {
    super.dispose();
  }

  void _handleClick(TapPosition tapPos, LatLng latLong) {
    print(latLong);
    if (_action == "marker") {
      bool markerAdded = true;
      Marker marker = makeMarker(latLong);
      for (var marker in _markers) {
        if (dist(latLong, marker.point) <= 0.003) {
          print("Marker already set at ${marker.point}");
          markerAdded = false;
          break;
        }
      }
      if (markerAdded) {
        setState(() {
          _markers.add(marker);
        });
      }
    } else if (_action == "route") {
      if (_polylines.last.points.length < 2) {
        for (var marker in _markers) {
          if (dist(latLong, marker.point) <= 0.003) {
            LatLng pt1 = _polylines.last.points[0];
            LatLng pt2 = marker.point;
            Marker end = makeArrow(pt1, pt2);

            if (_polylines.last.points.first == pt2) {
              _polylines.removeLast();
              break;
            }

            setState(() {
              _polylines.last.points.add(pt2);
              _endMarkers.add(end);
            });
            break;
          }
        }
      } else {
        for (var marker in _markers) {
          if (dist(latLong, marker.point) <= 0.003) {
            Polyline poly = Polyline(
              points: [marker.point],
              color: Colors.red,
              strokeWidth: 1.5,
            );
            setState(() {
              _polylines.add(poly);
            });
            break;
          }
        }
      }
    } else if (_action == "delete") {
      LatLng matchingPoint = latLong;
      bool hasMatchingPoint = false;
      for (var marker in _markers) {
        if (dist(latLong, marker.point) <= 0.003) {
          hasMatchingPoint = true;
          matchingPoint = marker.point;
          break;
        }
      }
      if (hasMatchingPoint) {
        List<Polyline> polyToRemove = [];

        for (var poly in _polylines) {
          if (poly.points[0] == matchingPoint) {
            polyToRemove.add(poly);
            _endMarkers.removeWhere((element) =>
                element.point == getArrowPos(poly.points[0], poly.points[1]));
          } else if (poly.points[1] == matchingPoint) {
            polyToRemove.add(poly);
            _endMarkers.removeWhere((element) =>
                element.point == getArrowPos(poly.points[0], poly.points[1]));
          }
        }
        for (var poly in polyToRemove) {
          _polylines.remove(poly);
        }
        _markers.removeWhere((element) => element.point == matchingPoint);
        setState(() {
          _polylines;
          _endMarkers;
          _markers;
        });
      }
    }
  }

  Marker makeMarker(LatLng latLong) {
    return Marker(
      width: 40,
      height: 40,
      point: latLong,
      builder: (contex) => const Icon(
        Icons.clear,
        size: 30,
        color: Color.fromARGB(255, 0, 0, 0),
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  Marker makeArrow(LatLng latLong1, LatLng latLong2) {
    return Marker(
      width: 10,
      height: 10,
      point: getArrowPos(latLong1, latLong2),
      builder: (contex) => const Icon(
        Icons.circle,
        size: 10,
        color: Colors.red,
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  // Construction du Widget de la page Carte
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: map(),
          ),
          Positioned(
            bottom: 10,
            right: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        color: const Color.fromARGB(220, 255, 255, 255),
                        child: const Text(
                          "Placer un point",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: FloatingActionButton(
                        backgroundColor: Colors.blue,
                        child: const Icon(Icons.location_on),
                        onPressed: () => setState(() {
                          _action = _action == "marker" ? "" : "marker";
                        }),
                      )
                    )
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        color: const Color.fromARGB(220, 255, 255, 255),
                        child: const Text(
                          "Créer une route",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: FloatingActionButton(
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.route),
                        onPressed: () => setState(() {
                          if (_action == "route") {
                            _action = "";
                          } else {
                            _action = "route";
                          }
                        }),
                      )
                    )
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        color: const Color.fromARGB(220, 255, 255, 255),
                        child: const Text(
                          "Supprimer un point"
                          ,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: FloatingActionButton(
                        backgroundColor: Colors.red,
                        child: const Icon(Icons.delete),
                        onPressed: () => setState(() {
                          _action = _action == "delete" ? "" : "delete";
                        }),
                      )
                    )
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        color: const Color.fromARGB(220, 255, 255, 255),
                        child: const Text(
                          "Sauvegarder",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: FloatingActionButton(
                        backgroundColor: Colors.orange,
                        child: const Icon(Icons.save),
                        onPressed: saveJson,
                      )
                    )
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        color: const Color.fromARGB(220, 255, 255, 255),
                        child: const Text(
                          "Charger",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 10,
                          ),
                        ),
                      )
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: FloatingActionButton(
                          backgroundColor: Colors.purple,
                          child: const Icon(Icons.refresh),
                          onPressed: loadJson),
                    )
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // Construction du Widget de la carte
  Widget map() {
    return FlutterMap(
      options: MapOptions(
        center: LatLng(widget.center[0], widget.center[1]),
        zoom: widget.startZoom,
        maxZoom: 20.0,
        minZoom: 5,
        onTap: _handleClick,
      ),
      children: [
        tileLayer(),
        markerLayer(),
        endMarkerLayer(),
        polylineLayer(),
      ],
    );
  }

  // Construction du Widget correspondant aux tiles de la carte
  Widget tileLayer() {
    return TileLayerWidget(
        options: TileLayerOptions(
      urlTemplate: "https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
      subdomains: ['a', 'b', 'c'],
    ));
  }

  // Construction du Widget correspondant aux polylines de la carte
  Widget polylineLayer() {
    return PolylineLayerWidget(
      options: PolylineLayerOptions(
        polylines: _polylines,
      ),
    );
  }

  Widget markerLayer() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: _markers,
    ));
  }

  Widget endMarkerLayer() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: _endMarkers,
    ));
  }
}
