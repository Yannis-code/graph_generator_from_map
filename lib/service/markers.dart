import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MarkerMaker {

  static Marker getMarker(LatLng pos, String type) {
    switch (type) {
      case "parking":
        return MarkerMaker.makeParkingMarker(pos);
      case "door":
        return MarkerMaker.makeDoor(pos);
      case "classroom":
        return MarkerMaker.makeInside(pos);
      case "stairs":
        return MarkerMaker.makeStairs(pos);
      default:
        return MarkerMaker.makeMarker(pos);
    }
  }

  static LatLng getArrowPos(LatLng latLong1, LatLng latLong2) {
    double latDist = (latLong2.latitude - latLong1.latitude);
    double lonDist = (latLong2.longitude - latLong1.longitude);
    double endLat = latDist * 0.9 + latLong1.latitude;
    double endLon = lonDist * 0.9 + latLong1.longitude;
    return LatLng(endLat, endLon);
  }

  static Marker makeMarker(LatLng latLong) {
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

  static Marker makeParkingMarker(LatLng latLong) {
    return Marker(
      width: 40,
      height: 40,
      point: latLong,
      builder: (contex) => Stack(
        alignment: Alignment.center,
        children: [
          const Center(
              child: Icon(
            Icons.clear,
            size: 30,
            color: Colors.black,
          )),
          Positioned(
              top: 0,
              child: Container(
                width: 20,
                height: 20,
                color: const Color.fromARGB(175, 255, 255, 255),
                child: const Icon(
                  Icons.local_parking,
                  size: 20,
                  color: Colors.blue,
                ),
              )),
        ],
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  static Marker makeDoor(LatLng latLong) {
    return Marker(
      width: 40,
      height: 40,
      point: latLong,
      builder: (contex) => Stack(
        alignment: Alignment.center,
        children: [
          const Center(
              child: Icon(
            Icons.clear,
            size: 30,
            color: Colors.orange,
          )),
          Positioned(
              top: 0,
              child: Container(
                width: 20,
                height: 20,
                color: const Color.fromARGB(175, 255, 255, 255),
                child: const Icon(
                  Icons.door_front_door,
                  size: 20,
                  color: Colors.orange,
                ),
              )),
        ],
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  static Marker makeStairs(LatLng latLong) {
    return Marker(
      width: 40,
      height: 40,
      point: latLong,
      builder: (contex) => Stack(
        alignment: Alignment.center,
        children: [
          const Center(
              child: Icon(
            Icons.clear,
            size: 30,
            color: Colors.red,
          )),
          Positioned(
              top: 0,
              child: Container(
                width: 20,
                height: 20,
                color: const Color.fromARGB(175, 255, 255, 255),
                child: const Icon(
                  Icons.stairs,
                  size: 20,
                  color: Colors.red,
                ),
              )),
        ],
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  static Marker makeInside(LatLng latLong) {
    return Marker(
      width: 40,
      height: 40,
      point: latLong,
      builder: (contex) => Stack(
        alignment: Alignment.center,
        children: [
          const Center(
              child: Icon(
            Icons.clear,
            size: 30,
            color: Colors.green,
          )),
          Positioned(
              top: 0,
              child: Container(
                width: 20,
                height: 20,
                color: const Color.fromARGB(175, 255, 255, 255),
                child: const Icon(
                  Icons.house,
                  size: 20,
                  color: Colors.green,
                ),
              )),
        ],
      ),
      anchorPos: AnchorPos.align(AnchorAlign.center),
    );
  }

  static Marker makeArrow(LatLng latLong1, LatLng latLong2) {
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

}