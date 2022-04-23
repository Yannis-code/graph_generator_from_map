// Import des packages flutter classiques

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Import des packages dart utiles pour les usage d'une carte
//
// dart:collection -> Fonctions de hashage
// dart:convert    -> Conversion des fichiers locaux
// dart:async      -> StreamControl
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
import 'package:path_generator/service/floyd_warshall.dart';
import 'package:path_generator/utils/ray_casting.dart';
import 'package:path_generator/service/geodata_service.dart';
import 'package:path_generator/service/markers.dart';
import 'package:path_generator/view/widgets/search_field.dart';
import 'package:positioned_tap_detector_2/positioned_tap_detector_2.dart';
import 'package:path_generator/service/file_manager.dart';
import 'package:path_generator/utils/spacial.dart';

class Carte extends StatefulWidget {
  const Carte({Key? key}) : super(key: key);

  @override
  _CarteState createState() => _CarteState();
}

// Classe de la map affichée
class _CarteState extends State<Carte> {
  late final MapController mapController;
  final ValueNotifier<String> edition = ValueNotifier("");
  final ValueNotifier<String> markerType = ValueNotifier("generic");
  final ValueNotifier<String> routingType = ValueNotifier("");
  final TextEditingController searchController = TextEditingController();
  final Map minSpaceMap = {
    "generic": 0.003,
    "parking": 0.003,
    "door": 0.0015,
    "stairs": 0.001,
    "classroom": 0.001,
  };

  int _floor = 0;
  double rotation = 0.0;
  bool _showPolygons = false;
  List<Polygon> _polygons = [];
  Map<String, dynamic> currentPoly = {};
  List<String> classroomList = [];
  Map<String, dynamic> _stages = {
    "0": {"polylines": <dynamic>[], "markers": <dynamic>[]},
    "1": {"polylines": <dynamic>[], "markers": <dynamic>[]},
    "2": {"polylines": <dynamic>[], "markers": <dynamic>[]},
    "3": {"polylines": <dynamic>[], "markers": <dynamic>[]},
  };

  Future<void> loadPolygons() async {
    List<Polygon> polys = await GeoJson.buildPolygons();
    if (mounted) {
      setState(() {
        _polygons = polys;
      });
    }
  }

  Future<void> loadClassroomList() async {
    final String response =
        await rootBundle.loadString('assets/classroomList.json');
    List<String> load = List.castFrom(await json.decode(response));
    setState(() {
      classroomList = load;
    });
  }

  Future<void> loadSave() async {
    Map<String, dynamic> stages = {
      "0": {"polylines": <dynamic>[], "markers": <dynamic>[]},
      "1": {"polylines": <dynamic>[], "markers": <dynamic>[]},
      "2": {"polylines": <dynamic>[], "markers": <dynamic>[]},
      "3": {"polylines": <dynamic>[], "markers": <dynamic>[]},
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

        Map<String, dynamic> polyOptions = {
          "startType": options["type"],
          "endType": connectionOpt["type"],
          "type":
              options["type"] == connectionOpt["type"] ? options["type"] : ""
        };

        stages["${min(options['floor'] as int, connectionOpt["floor"] as int)}"]
                ?["polylines"]
            .add({
          "polyline": poly,
          "pointer": MarkerMaker.makeArrow(startLatLng, endLatLng),
          "options": polyOptions,
        });
      }
      stages["${options['floor']}"]?["markers"].add({
        "marker": MarkerMaker.getMarker(startLatLng, options["type"]),
        "options": options,
      });
    }
    setState(() {
      _stages = stages;
    });
  }

  Future<void> save() async {
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
        for (var poly in _stages[key]?["polylines"]) {
          LatLng start = poly["polyline"].points.first;
          LatLng end = poly["polyline"].points.last;

          var endPoint = _stages[key]?["markers"].firstWhere((element) {
            return element["marker"].point == end;
          }, orElse: () => {});
          if (endPoint.isEmpty) {
            endPoint = _stages["${int.parse(key) + 1}"]?["markers"]
                .firstWhere((element) {
              return element["marker"].point == end &&
                  element["options"]["type"] == "stairs";
            });
          }

          String startString = "${start.latitude}, ${start.longitude}";
          String endString = "${end.latitude}, ${end.longitude}";
          double distance = dist(start, end);

          Map<String, dynamic> value = {
            "options": endPoint["options"],
            "point": [end.latitude, end.longitude]
          };
          value["options"]["distance"] = distance;

          if (!graph.containsKey(startString)) {
            graph[startString] = {"options": {}, "connections": []};
            var matching = _stages[key]?["markers"].firstWhere((element) {
              return element["marker"].point == start;
            }, orElse: () => {});
            if (matching.isEmpty) {
              matching = _stages["${int.parse(key) + 1}"]?["markers"]
                  .firstWhere((element) {
                return element["marker"].point == end &&
                    element["options"]["type"] == "stairs";
              });
            }
            outputs[matching["options"]["type"]]?.add([
              matching["options"],
              [start.latitude, start.longitude]
            ]);
            if (RayCasting.isInsidePolygons(_polygons, start)) {
              outputs["inside"]?.add([
                matching["options"],
                [start.latitude, start.longitude]
              ]);
            } else {
              outputs["outside"]?.add([
                matching["options"],
                [start.latitude, start.longitude]
              ]);
            }
            graph[startString]["options"] = matching["options"];
            outputs["global"]?.add([
              matching["options"],
              [start.latitude, start.longitude]
            ]);
          }
          if (!graph.containsKey(endString)) {
            graph[endString] = {"options": {}, "connections": []};
            var matching = _stages[key]?["markers"].firstWhere((element) {
              return element["marker"].point == end;
            }, orElse: () => {});
            if (matching.isEmpty) {
              matching = _stages["${int.parse(key) + 1}"]?["markers"]
                  .firstWhere((element) {
                return element["marker"].point == end &&
                    element["options"]["type"] == "stairs";
              });
            }
            outputs[matching["options"]["type"]]?.add([
              matching["options"],
              [end.latitude, end.longitude]
            ]);
            if (RayCasting.isInsidePolygons(_polygons, end)) {
              outputs["inside"]?.add([
                matching["options"],
                [end.latitude, end.longitude]
              ]);
            } else {
              outputs["outside"]?.add([
                matching["options"],
                [end.latitude, end.longitude]
              ]);
            }
            graph[endString]["options"] = matching["options"];
            outputs["global"]?.add([
              matching["options"],
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

  void handleClick(TapPosition tapPos, LatLng tapGeo) {
    if (edition.value == "marker") {
      handleMarker(tapGeo);
    } else if (edition.value == "route") {
      handleRouting(tapGeo);
    } else if (edition.value == "delete") {
      handleDeletion(tapGeo);
    }
  }

  void handleMarker(LatLng tapGeo) {
    bool markerAdded = !_stages["$_floor"]?["markers"].any((element) {
      return element["options"]["type"] == markerType.value &&
          dist(tapGeo, element["marker"].point) < minSpaceMap[markerType.value];
    });

    if (markerAdded) {
      bool labelSet = true;
      late Marker marker;
      Map options = {};
      options["floor"] = _floor;
      options["type"] = markerType.value;
      marker = MarkerMaker.getMarker(tapGeo, markerType.value);
      if (markerType.value == "classroom") {
        if (!checkValidity(searchController.text, classroomList)) {
          debugPrint("Classroom name invalid");
          labelSet = false;
        } else {
          options["name"] = searchController.text;
        }
      }

      if (labelSet) {
        setState(() {
          _stages["$_floor"]?["markers"]
              .add({"options": options, "marker": marker});
        });
      }
    } else {
      debugPrint(
          "Marker of type '${markerType.value}' too from $tapGeo (<${minSpaceMap[markerType.value] * 1000}m)");
    }
  }

  void handleRouting(LatLng tapGeo) {
    if (currentPoly["polyline"].points.isNotEmpty) {
      if (_stages["$_floor"]?["markers"].isNotEmpty) {
        dynamic closest =
            getClosestMarkers(tapGeo, _stages["$_floor"]?["markers"]);
        if (_floor < 3) {
          dynamic closestStairsSup =
              getClosestStairsSup(tapGeo, _stages["${_floor + 1}"]?["markers"]);
          if (closestStairsSup.isNotEmpty &&
              dist(tapGeo, closestStairsSup["marker"].point) <
                  dist(tapGeo, closest["marker"].point)) {
            closest = closestStairsSup;
          }
        }
        if (dist(closest["marker"].point, tapGeo) <
            minSpaceMap[closest["options"]["type"]]) {
          LatLng pt1 = currentPoly["polyline"].points.first;
          LatLng pt2 = closest["marker"].point;

          if (pt1 != pt2) {
            late Polyline poly;
            late Marker end2;
            if (routingType.value != "oriented") {
              poly = Polyline(
                points: [pt2, pt1],
                color: Colors.red,
                strokeWidth: 1.5,
              );
              end2 = MarkerMaker.makeArrow(pt2, pt1);
            }
            currentPoly["polyline"].points.add(pt2);
            Marker pointer = MarkerMaker.makeArrow(pt1, pt2);

            Map<String, dynamic> optionsPoly1 = {
              "startType": currentPoly["options"]["startType"],
              "endType": closest["options"]["type"],
              "type": currentPoly["options"]["startType"] ==
                      closest["options"]["type"]
                  ? closest["options"]["type"]
                  : ""
            };

            Map<String, dynamic> optionsPoly2 = {
              "startType": closest["options"]["type"],
              "endType": currentPoly["options"]["startType"],
              "type": currentPoly["options"]["startType"] ==
                      closest["options"]["type"]
                  ? closest["options"]["type"]
                  : ""
            };

            setState(() {
              currentPoly;
              _stages["$_floor"]?["polylines"].add({
                "polyline": currentPoly["polyline"],
                "options": optionsPoly1,
                "pointer": pointer
              });
              if (routingType.value != "oriented") {
                _stages["$_floor"]?["polylines"].add({
                  "polyline": poly,
                  "options": optionsPoly2,
                  "pointer": end2
                });
              }
            });
          }
          currentPoly = {
            "polyline": Polyline(
              points: [],
              color: Colors.red,
              strokeWidth: 1.5,
            ),
            "options": {},
          };
        }
      }
    } else {
      if (_stages["$_floor"]?["markers"].isNotEmpty) {
        dynamic closest =
            getClosestMarkers(tapGeo, _stages["$_floor"]?["markers"]);
        if (_floor < 3) {
          dynamic closestStairsSup =
              getClosestStairsSup(tapGeo, _stages["${_floor + 1}"]?["markers"]);
          if (closestStairsSup.isNotEmpty &&
              dist(tapGeo, closestStairsSup["marker"].point) <
                  dist(tapGeo, closest["marker"].point)) {
            closest = closestStairsSup;
          }
        }
        if (dist(closest["marker"].point, tapGeo) <
            minSpaceMap[closest["options"]["type"]]) {
          currentPoly["polyline"].points.add(closest["marker"].point);
          currentPoly["options"]["startType"] = closest["options"]["type"];
        }
      }
    }
  }

  void handleDeletion(LatLng tapGeo) {
    dynamic closest = getClosestMarkers(tapGeo, _stages["$_floor"]?["markers"]);
    if (_floor < 3) {
      dynamic closestStairsSup =
          getClosestStairsSup(tapGeo, _stages["${_floor + 1}"]?["markers"]);
      if (closestStairsSup.isNotEmpty &&
          dist(tapGeo, closestStairsSup["marker"].point) <
              dist(tapGeo, closest["marker"].point)) {
        closest = closestStairsSup;
      }
    }

    if (dist(tapGeo, closest["marker"].point) <
        minSpaceMap[closest["options"]["type"]]) {
      List<dynamic> polyToRemove = [];
      for (var poly in _stages["$_floor"]?["polylines"]) {
        if (poly["polyline"].points.first == closest["marker"].point) {
          polyToRemove.add(poly);
        } else if (poly["polyline"].points.last == closest["marker"].point) {
          polyToRemove.add(poly);
        }
      }
      for (var poly in polyToRemove) {
        _stages["$_floor"]?["polylines"].remove(poly);
      }
      setState(() {
        _stages["$_floor"]?["markers"].remove(closest);
      });
      if (_floor > 0) {
        List<dynamic> polyToRemove = [];
        for (var poly in _stages["${_floor - 1}"]?["polylines"]) {
          if (poly["polyline"].points.first == closest["marker"].point &&
              poly["options"]["startType"] == "stairs") {
            polyToRemove.add(poly);
          } else if (poly["polyline"].points.last == closest["marker"].point &&
              poly["options"]["endType"] == "stairs") {
            polyToRemove.add(poly);
          }
        }
        for (var poly in polyToRemove) {
          _stages["${_floor - 1}"]?["polylines"].remove(poly);
        }
        setState(() {
          _stages["${_floor - 1}"]?["markers"].remove(closest);
        });
      }
      if (_floor < 3) {
        List<dynamic> polyToRemove = [];
        for (var poly in _stages["${_floor + 1}"]?["polylines"]) {
          if (poly["polyline"].points.first == closest["marker"].point &&
              poly["options"]["startType"] == "stairs") {
            polyToRemove.add(poly);
          } else if (poly["polyline"].points.end == closest["marker"].point &&
              poly["options"]["endType"] == "stairs") {
            polyToRemove.add(poly);
          }
        }
        for (var poly in polyToRemove) {
          _stages["${_floor + 1}"]?["polylines"].remove(poly);
        }
        setState(() {
          _stages["${_floor + 1}"]?["markers"].remove(closest);
        });
      }
    }
  }

  // Initialisation des state du widget
  @override
  void initState() {
    super.initState();
    loadPolygons();
    loadClassroomList();
    mapController = MapController();
    currentPoly = {
      "polyline": Polyline(
        points: [],
        color: Colors.red,
        strokeWidth: 1.5,
      ),
      "options": {},
    };
  }

  // Fermeture des Stream de control lorsque la Carte n'est plus affichée
  @override
  void dispose() {
    edition.dispose();
    markerType.dispose();
    routingType.dispose();
    searchController.dispose();
    super.dispose();
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
                      if (edition.value == "marker") {
                        markerType.value = "generic";
                      }
                      edition.value = edition.value == "marker" ? "" : "marker";
                    },
                    label: const Text("Placer un point"),
                    icon: const Icon(Icons.location_on),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () {
                      edition.value = (edition.value == "route") ? "" : "route";
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
                      edition.value = edition.value == "delete" ? "" : "delete";
                    },
                    label: const Text("Supprimer un point"),
                    icon: const Icon(Icons.delete),
                    backgroundColor: Colors.red,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: save,
                    label: const Text("Sauvegarder"),
                    icon: const Icon(Icons.save),
                    backgroundColor: Colors.pink,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: loadSave,
                    label: const Text("Charger"),
                    icon: const Icon(Icons.refresh),
                    backgroundColor: Colors.purple,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: FloatingActionButton.extended(
                    onPressed: () async {
                      await save();
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
                valueListenable: edition,
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
                                markerType.value =
                                    (markerType.value == "classroom")
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
                                markerType.value = (markerType.value == "door")
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
                                markerType.value =
                                    (markerType.value == "stairs")
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
                                markerType.value =
                                    (markerType.value == "parking")
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
                                routingType.value =
                                    (routingType.value == "oriented")
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
                valueListenable: markerType,
                builder: (context, value, _) {
                  if (value == "classroom") {
                    return SizedBox(
                      width: 400,
                      height: 50,
                      child: searchField(searchController, classroomList),
                    );
                  }
                  return const SizedBox();
                }),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ValueListenableBuilder<String>(
                valueListenable: edition,
                builder: (context, value, _) {
                  if (value == "marker") {
                    return ValueListenableBuilder<String>(
                      valueListenable: markerType,
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
                      valueListenable: routingType,
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
        center: LatLng(45.758829, 3.111014),
        zoom: 18,
        maxZoom: 23.0,
        minZoom: 5,
        onTap: handleClick,
      ),
      children: [
        tiles(),
        if (_showPolygons) polygons(),
        plan(),
        polyline(),
        pointers(),
        markers(),
      ],
    );
  }

  List<Polyline> getPolylinesToDisplay() {
    List<Polyline> polylines = _stages["$_floor"]?["polylines"]
        .map<Polyline>((e) => e["polyline"] as Polyline)
        .toList();
    if (_floor < 3) {
      polylines += _stages["${_floor + 1}"]?["polylines"]
          .where((e) => e["options"]["type"] == "stairs")
          .map<Polyline>((e) => e["polyline"] as Polyline)
          .toList();
    }
    return polylines;
  }

  Widget polyline() {
    return PolylineLayerWidget(
      options: PolylineLayerOptions(polylines: getPolylinesToDisplay()),
    );
  }

  List<Marker> getMarkersToDisplay() {
    List<Marker> markers = _stages["$_floor"]?["markers"]
        .map<Marker>((e) => e["marker"] as Marker)
        .toList();
    if (_floor < 3) {
      markers += _stages["${_floor + 1}"]?["markers"]
          .where((e) => e["options"]["type"] == "stairs")
          .map<Marker>((e) => e["marker"] as Marker)
          .toList();
    }
    return markers;
  }

  Widget markers() {
    return MarkerLayerWidget(
      options: MarkerLayerOptions(markers: getMarkersToDisplay()),
    );
  }

  Widget polygons() {
    return PolygonLayerWidget(
      options: PolygonLayerOptions(polygons: _polygons),
    );
  }

  Widget tiles() {
    return TileLayerWidget(
        options: TileLayerOptions(
      tileSize: 256,
      maxZoom: 20,
      urlTemplate: "https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png",
      subdomains: ['a', 'b', 'c'],
    ));
  }

  Widget plan() {
    return TileLayerWidget(
        options: TileLayerOptions(
      tileSize: 256,
      minZoom: 20.5,
      maxZoom: 23,
      urlTemplate: "https://perso.isima.fr/~yaroche1/tiles/{z}_{x}_{y}.png",
      backgroundColor: Colors.transparent,
    ));
  }

  List<Marker> getPointersToDisplay() {
    List<Marker> pointers = _stages["$_floor"]?["polylines"]
        .map<Marker>((e) => e["pointer"] as Marker)
        .toList();
    if (_floor < 3) {
      pointers += _stages["${_floor + 1}"]?["polylines"]
          .where((e) => e["options"]["type"] == "stairs")
          .map<Marker>((e) => e["pointer"] as Marker)
          .toList();
    }
    return pointers;
  }

  Widget pointers() {
    return MarkerLayerWidget(
        options: MarkerLayerOptions(
      markers: getPointersToDisplay(),
    ));
  }

}
