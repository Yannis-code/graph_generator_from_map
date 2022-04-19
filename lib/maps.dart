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
import 'package:path_generator/floyd_warshall.dart';
import 'package:path_generator/routing_service.dart';
import 'package:path_generator/widgets/markers.dart';
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
      this.center = const <double>[45.758829, 3.111014],
      this.startZoom = 18.25,
      this.enableLocation = true,
      this.targetedBuilding = const <double>[]})
      : super(key: key);

  @override
  _CarteState createState() => _CarteState();
}

// Classe de la map affichée
class _CarteState extends State<Carte> {
  final Map minSpaceMap = {
    "generic": 0.003,
    "parking": 0.003,
    "door": 0.0015,
    "classroom": 0.001,
  };

  // Déclaration des listes d'objet à afficher sur la map
  List<Polygon> _polygons = [];
  List<dynamic> _markers = [];
  List<Marker> _markersList = [];
  List<Marker> _directionMarkers = [];
  List<Polyline> _polylines = [];
  bool _showPolygons = false;

  final ValueNotifier<String> _action = ValueNotifier("");
  final ValueNotifier<String> _markerType = ValueNotifier("generic");
  final ValueNotifier<String> _routeType = ValueNotifier("");
  TextEditingController markerLabelController = TextEditingController();

  late final MapController mapController;
  double rotation = 0.0;

  var overlayImages = <OverlayImage>[
    OverlayImage(
        bounds: LatLngBounds(LatLng(51.5, -0.09), LatLng(48.8566, 2.3522)),
        opacity: 0.8,
        imageProvider: NetworkImage(
            'https://images.pexels.com/photos/231009/pexels-photo-231009.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=300&w=600')),
  ];

  Future<void> _buildPolygons() async {
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

    if (!mounted) return;
    setState(() => _polygons = polygons);
  }

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

  Marker getClosest(Marker marker, List<Marker> markers) {
    Marker closest = markers[0];
    for (var mark in markers) {
      if (dist(marker.point, mark.point) < dist(marker.point, closest.point)) {
        closest = mark;
      }
    }
    return closest;
  }

  Future<void> loadJson() async {
    List<dynamic> markerss = [];
    List<Marker> markersGlobal = [];

    List<Marker> parking =
        await loadMarkerList(markersGlobal, "parking", "hashParking.json");
    for (var marker in parking) {
      markerss.add(["parking", marker, {}]);
    }
    List<Marker> door =
        await loadMarkerList(markersGlobal, "door", "hashDoor.json");
    for (var marker in door) {
      markerss.add(["door", marker, {}]);
    }
    List<Marker> generic =
        await loadMarkerList(markersGlobal, "generic", "hashGeneric.json");
    for (var marker in generic) {
      markerss.add(["generic", marker, {}]);
    }

    List<dynamic> loadInside =
        await FileManager.loadFromFile("hashInsideMarker.json");
    for (var classroom in loadInside) {
      LatLng classroomLatLng = LatLng(classroom[0][0], classroom[0][1]);
      Marker marker = MarkerMaker.makeInside(classroomLatLng);
      markerss.add([
        "classroom",
        marker,
        {"name": classroom[1]}
      ]);
      markersGlobal.add(marker);
    }

    List<Marker> endMarkers = [];
    List<Polyline> polylines = [];
    Map<dynamic, dynamic> load = await FileManager.loadFromFile("graph.json");
    for (var key in load.keys) {
      List<String> keyVal = key.split(", ");
      LatLng loadedLatLng =
          LatLng(double.parse(keyVal[0]), double.parse(keyVal[1]));
      for (var connected in load[key]) {
        LatLng connectedLatLng = LatLng(connected[0], connected[1]);
        Polyline poly = Polyline(
          points: [loadedLatLng, connectedLatLng],
          color: Colors.red,
          strokeWidth: 1.5,
        );
        Marker end = MarkerMaker.makeArrow(loadedLatLng, connectedLatLng);
        endMarkers.add(end);
        polylines.add(poly);
      }
    }
    setState(() {
      _markers = markerss;
      _markersList = markersGlobal;
      _directionMarkers = endMarkers;
      _polylines = polylines;
    });
  }

  Future<List<Marker>> loadMarkerList(
      List<dynamic> globalList, String type, String path) async {
    List<dynamic> data = await FileManager.loadFromFile(path);
    List<Marker> markers = [];
    for (var loadedMarker in data) {
      LatLng latLng = LatLng(loadedMarker[0], loadedMarker[1]);
      late Marker marker;
      switch (type) {
        case "parking":
          marker = MarkerMaker.makeParkingMarker(latLng);
          break;
        case "door":
          marker = MarkerMaker.makeDoor(latLng);
          break;
        default:
          marker = MarkerMaker.makeMarker(latLng);
          break;
      }
      globalList.add(marker);
      markers.add(marker);
    }
    return markers;
  }

  Future<void> saveJson() async {
    Map<String, dynamic> graph = {};
    Set<List<double>> parkingMarkers = {};
    Set<List<dynamic>> classroomMarkers = {};
    Set<List<double>> doorMarkers = {};
    Set<List<double>> insideMarkers = {};
    Set<List<double>> outsideMarkers = {};
    Set<List<double>> allMarkers = {};
    Set<List<double>> genericMarkers = {};
    for (var poly in _polylines) {
      LatLng start = poly.points.first;
      LatLng end = poly.points.last;

      String startString = "${start.latitude}, ${start.longitude}";
      String endString = "${end.latitude}, ${end.longitude}";
      double distance = dist(start, end);

      List<double> value = [end.latitude, end.longitude, distance];

      if (!graph.containsKey(startString)) {
        graph[startString] = [];
        var matching = _markers.firstWhere((element) {
          return element[1].point == start;
        });
        if (matching[0] == "parking") {
          parkingMarkers.add([start.latitude, start.longitude]);
        } else if (matching[0] == "door") {
          doorMarkers.add([start.latitude, start.longitude]);
        } else if (matching[0] == "classroom") {
          classroomMarkers.add([
            [start.latitude, start.longitude],
            matching[2]["name"]
          ]);
        } else if (matching[0] == "generic") {
          genericMarkers.add([start.latitude, start.longitude]);
        }
        if (Routing.isInsidePolygons(_polygons, start)) {
          insideMarkers.add([start.latitude, start.longitude]);
        } else {
          outsideMarkers.add([start.latitude, start.longitude]);
        }
        allMarkers.add([start.latitude, start.longitude]);
      }
      if (!graph.containsKey(endString)) {
        graph[endString] = [];
        var matching = _markers.firstWhere((element) {
          return element[1].point == end;
        });
        if (matching[0] == "parking") {
          parkingMarkers.add([end.latitude, end.longitude]);
        } else if (matching[0] == "door") {
          doorMarkers.add([end.latitude, end.longitude]);
        } else if (matching[0] == "classroom") {
          classroomMarkers.add([
            [end.latitude, end.longitude],
            matching[2]["name"]
          ]);
        } else if (matching[0] == "generic") {
          genericMarkers.add([end.latitude, end.longitude]);
        }
        if (Routing.isInsidePolygons(_polygons, end)) {
          insideMarkers.add([end.latitude, end.longitude]);
        } else {
          outsideMarkers.add([end.latitude, end.longitude]);
        }
        allMarkers.add([end.latitude, end.longitude]);
      }
      if (!graph[startString].contains(value)) {
        graph[startString].add(value);
      }
    }
    await FileManager.writeToFile("hashInside.json", insideMarkers.toList());
    await FileManager.writeToFile("hashOutside.json", outsideMarkers.toList());
    await FileManager.writeToFile("hashParking.json", parkingMarkers.toList());
    await FileManager.writeToFile("hashGeneric.json", genericMarkers.toList());
    await FileManager.writeToFile(
        "hashInsideMarker.json", classroomMarkers.toList());
    await FileManager.writeToFile("hashDoor.json", doorMarkers.toList());
    await FileManager.writeToFile("hashGlobal.json", allMarkers.toList());
    await FileManager.writeToFile("graph.json", graph);
  }

  // Initialisation des state du widget
  @override
  void initState() {
    super.initState();
    _buildPolygons();
    mapController = MapController();
  }

  // Fermeture des Stream de control lorsque la Carte n'est plus affichée
  @override
  void dispose() {
    super.dispose();
  }

  void _handleClick(TapPosition tapPos, LatLng latLong) {
    print(latLong);
    if (_action.value == "marker") {
      bool markerAdded = !_markers.any((element) {
        return element[0] == _markerType.value &&
            dist(latLong, element[1].point) < minSpaceMap[_markerType.value];
      });

      
      if (markerAdded) {
        bool labelSet = true;
        late Marker marker;
        Map options = {};
        if (_markerType.value == "parking") {
          marker = MarkerMaker.makeParkingMarker(latLong);
        } else if (_markerType.value == "door") {
          marker = MarkerMaker.makeDoor(latLong);
        } else if (_markerType.value == "classroom") {
          if (markerLabelController.text == "") {
            print("Classroom name can not be empty");
            labelSet = false;
          }
          marker = MarkerMaker.makeInside(latLong);
          options = {"name": markerLabelController.text};
        } else if (_markerType.value == "generic") {
          marker = MarkerMaker.makeMarker(latLong);
        }
        if (labelSet) {
          setState(() {
            _markersList.add(marker);
            _markers.add([_markerType.value, marker, options]);
          });
        }
      } else {
        print(
            "Marker of type '${_markerType.value}' too from $latLong (<${minSpaceMap[_markerType.value] * 1000}m)");
      }
    } else if (_action.value == "route") {
      if (_polylines.isNotEmpty && _polylines.last.points.length < 2) {
        if (_markersList.isNotEmpty) {
          Marker test = MarkerMaker.makeMarker(latLong);
          Marker closest = getClosest(test, _markersList);
          if (dist(closest.point, latLong) < minSpaceMap["generic"]) {
            LatLng pt1 = _polylines.last.points.first;
            LatLng pt2 = closest.point;
            Marker end = MarkerMaker.makeArrow(pt1, pt2);

            if (_polylines.last.points.first == pt2) {
              _polylines.removeLast();
            } else {
              late Polyline poly;
              late Marker end2;
              if (_routeType.value != "oriented") {
                poly = Polyline(
                  points: [pt2, pt1],
                  color: Colors.red,
                  strokeWidth: 1.5,
                );
                end2 = MarkerMaker.makeArrow(pt2, pt1);
              }

              setState(() {
                _polylines.last.points.add(pt2);
                _directionMarkers.add(end);
                if (_routeType.value != "oriented") {
                  _polylines.add(poly);
                  _directionMarkers.add(end2);
                }
              });
            }
          }
        }
      } else {
        if (_markersList.isNotEmpty) {
          Marker test = MarkerMaker.makeMarker(latLong);
          Marker closest = getClosest(test, _markersList);
          if (dist(closest.point, latLong) < minSpaceMap["generic"]) {
            Polyline poly = Polyline(
              points: [closest.point],
              color: Colors.red,
              strokeWidth: 1.5,
            );
            setState(() {
              _polylines.add(poly);
            });
          }
        }
      }
    } else if (_action.value == "delete") {
      Marker marker = MarkerMaker.makeMarker(latLong);
      var closest = _markers.firstWhere(
        (element) {
          return dist(latLong, element[1].point) < 0.003;
        },
        orElse: () => [],
      );
      if (closest != []) {
        setState(() {
          _markersList.removeWhere((element) {
            return element.point == closest[1].point;
          });
          _markers.removeWhere((element) => element == closest);
        });
      }
      if (closest != []) {
        List<Polyline> polyToRemove = [];
        Marker closestMarker = closest[1];
        for (var poly in _polylines) {
          if (poly.points[0] == closestMarker.point) {
            polyToRemove.add(poly);
            _directionMarkers.removeWhere((element) =>
                element.point ==
                MarkerMaker.getArrowPos(poly.points[0], poly.points[1]));
          } else if (poly.points[1] == closestMarker.point) {
            polyToRemove.add(poly);
            _directionMarkers.removeWhere((element) =>
                element.point ==
                MarkerMaker.getArrowPos(poly.points[0], poly.points[1]));
          }
        }
        for (var poly in polyToRemove) {
          _polylines.remove(poly);
        }
        setState(() {
          _polylines;
          _markersList;
          _markers;
        });
      }
    }
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
              top: 20,
              left: 20,
              child: Container(
                color: const Color.fromARGB(220, 255, 255, 255),
                child: Row(
                  children: [
                    Switch(
                      value: _showPolygons,
                      onChanged: (val) {
                        setState(() {
                          _showPolygons = val;
                        });
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.all(5),
                      child: Text(
                        "Afficher les bâtiments",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
          Positioned(
            bottom: 10,
            right: 10,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      if (_action.value == "marker") {
                        _markerType.value = "";
                      }
                      _action.value = _action.value == "marker" ? "" : "marker";
                    },
                    label: const Text("Placer un point"),
                    icon: const Icon(Icons.location_on),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      _action.value = (_action.value == "route") ? "" : "route";
                    },
                    label: const Text("Créer une route"),
                    icon: const Icon(Icons.route),
                    backgroundColor: Colors.green,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      _action.value = _action.value == "delete" ? "" : "delete";
                    },
                    label: const Text("Supprimer un point"),
                    icon: const Icon(Icons.delete),
                    backgroundColor: Colors.red,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: saveJson,
                    label: const Text("Sauvegarder"),
                    icon: const Icon(Icons.save),
                    backgroundColor: Colors.pink,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: loadJson,
                    label: const Text("Charger"),
                    icon: const Icon(Icons.refresh),
                    backgroundColor: Colors.purple,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () async {
                      await saveJson();
                      await FloydWarshall.compute();
                    },
                    label: const Text("Calculer"),
                    icon: const Icon(Icons.computer),
                    backgroundColor: Colors.indigo,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 10,
            left: 10,
            child: ValueListenableBuilder<String>(
                valueListenable: _action,
                builder: (context, value, _) {
                  if (value == "marker") {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(5),
                          child: FloatingActionButton.extended(
                              backgroundColor: Colors.green,
                              icon: const Icon(Icons.house),
                              onPressed: () {
                                _markerType.value =
                                    (_markerType.value == "classroom")
                                        ? "generic"
                                        : "classroom";
                              },
                              label: const Text("Marker intérieur")),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(5),
                          child: FloatingActionButton.extended(
                              backgroundColor: Colors.orange,
                              icon: const Icon(Icons.door_front_door),
                              onPressed: () {
                                _markerType.value =
                                    (_markerType.value == "door")
                                        ? "generic"
                                        : "door";
                              },
                              label: const Text("Marker de Portes")),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(5),
                          child: FloatingActionButton.extended(
                              backgroundColor: Colors.white,
                              icon: const Icon(
                                Icons.local_parking,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                _markerType.value =
                                    (_markerType.value == "parking")
                                        ? "generic"
                                        : "parking";
                              },
                              label: const Text(
                                "Marker de Parking",
                                style: TextStyle(
                                  color: Colors.blue,
                                ),
                              )),
                        ),
                      ],
                    );
                  } else if (value == "route") {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(5),
                          child: FloatingActionButton.extended(
                              backgroundColor: Colors.green,
                              icon: const Icon(Icons.arrow_right_alt),
                              onPressed: () {
                                _routeType.value =
                                    (_routeType.value == "oriented")
                                        ? ""
                                        : "oriented";
                              },
                              label: const Text("Route orienté")),
                        ),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              height: 50,
              width: 500,
              color: Colors.white,
              child: Slider(
                value: rotation,
                min: 0.0,
                max: 360,
                onChanged: (degree) {
                  setState(() {
                    rotation = degree;
                  });
                  mapController.rotate(degree);
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ValueListenableBuilder<String>(
                valueListenable: _markerType,
                builder: (context, value, _) {
                  if (value == "classroom") {
                    return SizedBox(
                      width: 400,
                      height: 50,
                      child: TextField(
                        controller: markerLabelController,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 15.0,
                          ),
                          fillColor: Colors.white,
                          filled: true,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: const BorderSide(width: 1.5)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30.0),
                              borderSide: BorderSide(
                                width: 1.5,
                                color: Theme.of(context).primaryColor,
                              )),
                          prefixIcon: const Icon(
                            Icons.abc,
                            size: 30,
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.cancel),
                            onPressed: () {
                              markerLabelController.text = "";
                            },
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox();
                }),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<String>(
                valueListenable: _action,
                builder: (context, value, _) {
                  if (value == "marker") {
                    return ValueListenableBuilder<String>(
                      valueListenable: _markerType,
                      builder: (context, type, _) {
                        if (type != "") {
                          return Container(
                              color: Colors.white,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 20),
                                  child: Text(
                                    type,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )));
                        }
                        return Container(
                            color: Colors.white,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 20),
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )));
                      },
                    );
                  } else if (value == "route") {
                    return ValueListenableBuilder<String>(
                      valueListenable: _routeType,
                      builder: (context, type, _) {
                        if (type != "") {
                          return Container(
                              color: Colors.white,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 20),
                                  child: Text(
                                    type,
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )));
                        }
                        return Container(
                            color: Colors.white,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 20),
                                child: Text(
                                  value,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )));
                      },
                    );
                  }
                  if (value != "") {
                    return Container(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 20),
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                }),
          ),
        ],
      ),
    );
  }

  // Construction du Widget de la carte
  Widget map() {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        center: LatLng(widget.center[0], widget.center[1]),
        zoom: widget.startZoom,
        maxZoom: 23.0,
        minZoom: 5,
        onTap: _handleClick,
      ),
      children: [
        tileLayer(),
        //info(),
        if (_showPolygons) polygonLayer(),
        alainDelpuch(),
        polylineLayer(),
        endMarkerLayer(),
        markerLayer(),
        OverlayImageLayerWidget(
          options: OverlayImageLayerOptions(
            overlayImages: overlayImages,
          ),
        )
      ],
    );
  }

  // Construction du Widget correspondant aux tiles de la carte
  Widget tileLayer() {
    return TileLayerWidget(
        options: TileLayerOptions(
      tileSize: 256,
      maxZoom: 20,
      urlTemplate: "https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
      subdomains: ['a', 'b', 'c'],
    ));
  }

  Widget alainDelpuch() {
    return TileLayerWidget(
        options: TileLayerOptions(
      tileSize: 256,
      minZoom: 20,
      maxZoom: 23,
      urlTemplate: "https://perso.isima.fr/~yaroche1/tiles/{z}_{x}_{y}.png",
      backgroundColor: Colors.transparent,
    ));
  }

  /* Widget info() {
    return TileLayerWidget(
        options: TileLayerOptions(
            tileSize: 250,
            maxZoom: 20,
            urlTemplate:
                "https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
            subdomains: ['a', 'b', 'c'],
            backgroundColor: Colors.transparent,
            tileBuilder: (context, _, tile) {
              return Container(
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.red, width: 1.0)),
                child: Text("${tile.coords.z},   ${tile.coords.x},   ${tile.coords.y}"),
              );
            }));
  } */

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
      markers: _markersList,
    ));
  }

  Widget endMarkerLayer() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: _directionMarkers,
    ));
  }

  Widget polygonLayer() {
    return PolygonLayerWidget(
      options: PolygonLayerOptions(polygons: _polygons),
    );
  }
}
