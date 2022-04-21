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
    "stairs": 0.001,
    "classroom": 0.001,
  };

  // Déclaration des listes d'objet à afficher sur la map
  List<Polygon> _polygons = [];

  Map<String, List<dynamic>> _stages = {
    "0": [<Polyline>[], <Marker>[], <dynamic>[]],
    "1": [<Polyline>[], <Marker>[], <dynamic>[]],
    "2": [<Polyline>[], <Marker>[], <dynamic>[]],
    "3": [<Polyline>[], <Marker>[], <dynamic>[]],
  };
  bool _showPolygons = false;

  final ValueNotifier<String> _action = ValueNotifier("");
  final ValueNotifier<String> _markerType = ValueNotifier("generic");
  final ValueNotifier<String> _routeType = ValueNotifier("");
  int _floor = 0;
  TextEditingController markerLabelController = TextEditingController();

  late final MapController mapController;
  double rotation = 0.0;

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

  dynamic getClosestMarkers(LatLng latLng, List<dynamic> markers) {
    dynamic closest = markers[0];
    for (var mark in markers) {
      if (dist(latLng, mark[1].point) < dist(latLng, closest[1].point)) {
        closest = mark;
      }
    }
    return closest;
  }

  Future<void> loadJson() async {
    Map<String, List<dynamic>> stages = {
      "0": [<Polyline>[], <Marker>[], <dynamic>[]],
      "1": [<Polyline>[], <Marker>[], <dynamic>[]],
      "2": [<Polyline>[], <Marker>[], <dynamic>[]],
      "3": [<Polyline>[], <Marker>[], <dynamic>[]],
    };

    Map<dynamic, dynamic> load = await FileManager.loadFromFile("graph.json");
    for (var key in load.keys) {
      List<String> keyVal = key.split(", ");
      LatLng startLatLng =
          LatLng(double.parse(keyVal[0]), double.parse(keyVal[1]));

      Map<String, dynamic> options = load[key]["options"];
      List<dynamic> connections = load[key]["connections"];

      for (var connection in connections) {
        Map<String, dynamic> connectionOpt = connection["options"];
        List<dynamic> connectionData = connection["point"];
        LatLng endLatLng = LatLng(connectionData[0], connectionData[1]);
        Polyline poly = Polyline(
          points: [startLatLng, endLatLng],
          color: Colors.red,
          strokeWidth: 1.5,
        );
        MarkerMaker.getMarker(startLatLng, options["type"]);
        stages["${options['floor']}"]?[1]
            .add(MarkerMaker.makeArrow(startLatLng, endLatLng));
        stages["${options['floor']}"]?[0].add(poly);
      }
      Marker marker = MarkerMaker.getMarker(startLatLng, options["type"]);
      stages["${options['floor']}"]?[2].add([options, marker]);
    }
    setState(() {
      _stages = stages;
    });
  }

  Future<void> saveJson() async {
    Map<String, dynamic> graph = {};
    Map<String, Set<dynamic>> outputs = {
      "parking": {},
      "door": {},
      "classroom": {},
      "generic": {},
      "inside": {},
      "outside": {},
      "global": {},
    };

    for (var key in _stages.keys) {
      if (key != "global") {
        for (var poly in _stages[key]?[0]) {
          LatLng start = poly.points.first;
          LatLng end = poly.points.last;

          var endPoint = _stages[key]?[2].firstWhere((element) {
            return element[1].point == end;
          });

          String startString = "${start.latitude}, ${start.longitude}";
          String endString = "${end.latitude}, ${end.longitude}";
          double distance = dist(start, end);

          Map<String, dynamic> value = {
            "options": endPoint[0],
            "point": [end.latitude, end.longitude]
          };
          value["options"]["distance"] = distance;

          if (!graph.containsKey(startString)) {
            graph[startString] = {"options": {}, "connections": []};
            var matching = _stages[key]?[2].firstWhere((element) {
              return element[1].point == start;
            });
            outputs[matching[0]["type"]]?.add([
              matching[0],
              [start.latitude, start.longitude]
            ]);
            if (Routing.isInsidePolygons(_polygons, start)) {
              outputs["inside"]?.add([
                matching[0],
                [start.latitude, start.longitude]
              ]);
            } else {
              outputs["outside"]?.add([
                matching[0],
                [start.latitude, start.longitude]
              ]);
            }
            graph[startString]["options"] = matching[0];
            outputs["global"]?.add([
              matching[0],
              [start.latitude, start.longitude]
            ]);
          }
          if (!graph.containsKey(endString)) {
            graph[endString] = {"options": {}, "connections": []};
            var matching = _stages[key]?[2].firstWhere((element) {
              return element[1].point == end;
            });
            outputs[matching[0]["type"]]?.add([
              matching[0],
              [end.latitude, end.longitude]
            ]);
            if (Routing.isInsidePolygons(_polygons, end)) {
              outputs["inside"]?.add([
                matching[0],
                [end.latitude, end.longitude]
              ]);
            } else {
              outputs["outside"]?.add([
                matching[0],
                [end.latitude, end.longitude]
              ]);
            }
            graph[endString]["options"] = matching[0];
            outputs["global"]?.add([
              matching[0],
              [end.latitude, end.longitude]
            ]);
          }
          if (!graph[startString]["connections"].contains(value)) {
            graph[startString]["connections"].add(value);
          }
        }
      }
    }

    for (var key in outputs.keys) {
      await FileManager.writeToFile("hash_$key.json", outputs[key]?.toList());
    }
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
      bool markerAdded = !_stages["$_floor"]?[2].any((element) {
        return element[0]["type"] == _markerType.value &&
            dist(latLong, element[1].point) < minSpaceMap[_markerType.value];
      });

      if (markerAdded) {
        bool labelSet = true;
        late Marker marker;
        Map options = {};
        options["floor"] = _floor;
        options["type"] = _markerType.value;
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
          options["name"] = markerLabelController.text;
        } else if (_markerType.value == "stairs") {
          marker = MarkerMaker.makeStairs(latLong);
        } else if (_markerType.value == "generic") {
          marker = MarkerMaker.makeMarker(latLong);
        }

        if (labelSet) {
          setState(() {
            _stages["$_floor"]?[2].add([options, marker]);
          });
        }
      } else {
        print(
            "Marker of type '${_markerType.value}' too from $latLong (<${minSpaceMap[_markerType.value] * 1000}m)");
      }
    } else if (_action.value == "route") {
      if (_stages["$_floor"]?[0].isNotEmpty &&
          _stages["$_floor"]?[0].last.points.length < 2) {
        if (_stages["$_floor"]?[2].isNotEmpty) {
          dynamic closest = getClosestMarkers(latLong, _stages["$_floor"]?[2]);
          if (dist(closest[1].point, latLong) <
              minSpaceMap[closest[0]["type"]]) {
            LatLng pt1 = _stages["$_floor"]?[0].last.points.first;
            LatLng pt2 = closest[1].point;
            Marker end = MarkerMaker.makeArrow(pt1, pt2);

            if (pt1 == pt2) {
              _stages["$_floor"]?[0].removeLast();
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
                _stages["$_floor"]?[0].last.points.add(pt2);
                _stages["$_floor"]?[1].add(end);
                if (_routeType.value != "oriented") {
                  _stages["$_floor"]?[0].add(poly);
                  _stages["$_floor"]?[1].add(end2);
                }
              });
            }
          }
        }
      } else {
        if (_stages["$_floor"]?[2].isNotEmpty) {
          dynamic closest = getClosestMarkers(latLong, _stages["$_floor"]?[2]);
          if (dist(closest[1].point, latLong) <
              minSpaceMap[closest[0]["type"]]) {
            Polyline poly = Polyline(
              points: [closest[1].point],
              color: Colors.red,
              strokeWidth: 1.5,
            );
            setState(() {
              _stages["$_floor"]?[0].add(poly);
            });
          }
        }
      }
    } else if (_action.value == "delete") {
      dynamic closest = getClosestMarkers(latLong, _stages["$_floor"]?[2]);
      if (dist(latLong, closest[1].point) < minSpaceMap[closest[0]["type"]]) {
        List<Polyline> polyToRemove = [];
        for (var poly in _stages["$_floor"]?[0]) {
          if (poly.points[0] == closest[1].point) {
            polyToRemove.add(poly);
            _stages["$_floor"]?[1].remove(
                MarkerMaker.getArrowPos(poly.points[0], poly.points[1]));
          } else if (poly.points[1] == closest[1].point) {
            polyToRemove.add(poly);
            _stages["$_floor"]?[1].remove(
                MarkerMaker.getArrowPos(poly.points[0], poly.points[1]));
          }
        }
        for (var poly in polyToRemove) {
          _stages["$_floor"]?[0].remove(poly);
        }
        setState(() {
          _stages["$_floor"]?[2].remove(closest);
          _stages["$_floor"]?[2].removeWhere((element) => element == closest);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
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
                  ),
                  Container(
                    color: const Color.fromARGB(220, 255, 255, 255),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.all(5),
                          child: Text(
                            "Etage affiché",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        DropdownButton<int>(
                            value: _floor,
                            items: <int>[0, 1, 2, 3, 4]
                                .map<DropdownMenuItem<int>>((int val) {
                              return DropdownMenuItem<int>(
                                value: val,
                                child: Text("$val"),
                              );
                            }).toList(),
                            onChanged: (int? newVal) {
                              setState(() {
                                _floor = newVal ?? _floor;
                              });
                              ;
                            }),
                      ],
                    ),
                  ),
                ],
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
                        _markerType.value = "generic";
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
                              backgroundColor: Colors.red,
                              icon: const Icon(Icons.stairs),
                              onPressed: () {
                                _markerType.value =
                                    (_markerType.value == "stairs")
                                        ? "generic"
                                        : "stairs";
                              },
                              label: const Text("Marker d'escalier")),
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
        if (false) info(),
        if (_showPolygons) polygonLayer(),
        alainDelpuch(),
        polylineLayer(),
        endMarkerLayer(),
        markerLayer(),
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
      minZoom: 20.5,
      maxZoom: 23,
      urlTemplate: "https://perso.isima.fr/~yaroche1/tiles/{z}_{x}_{y}.png",
      backgroundColor: Colors.transparent,
    ));
  }

  Widget info() {
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
                child: Text(
                    "${tile.coords.z},   ${tile.coords.x},   ${tile.coords.y}"),
              );
            }));
  }

  // Construction du Widget correspondant aux polylines de la carte
  Widget polylineLayer() {
    return PolylineLayerWidget(
      options: PolylineLayerOptions(polylines: _stages["$_floor"]?[0]),
    );
  }

  Widget markerLayer() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: _stages["$_floor"]?[2].map<Marker>((e) => e[1] as Marker).toList(),
    ));
  }

  Widget endMarkerLayer() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: _stages["$_floor"]?[1],
    ));
  }

  Widget polygonLayer() {
    return PolygonLayerWidget(
      options: PolygonLayerOptions(polygons: _polygons),
    );
  }
}
