import 'package:path_generator/file_manager.dart';

class FloydWarshall {
  static calculator(List<dynamic> distances, List<dynamic> predecessors) {
    for (var k = 0; k < distances.length; k++) {
      for (var i = 0; i < distances.length; i++) {
        for (var j = 0; j < distances.length; j++) {
          num potentialNewDistance = distances[i][k] + distances[k][j];
          if (potentialNewDistance < distances[i][j]) {
            distances[i][j] = potentialNewDistance;
            predecessors[i][j] = predecessors[k][j];
          }
        }
      }
    }
    return [distances, predecessors];
  }

  static initializer() async {
    Map<dynamic, dynamic> graph = await FileManager.loadFromFile("graph.json");
    Iterable<dynamic> keys = graph.keys;
    List<dynamic> hash = [];
    for (var key in keys) {
      List<String> split = key.split(", ");
      hash.add([double.parse(split[0]), double.parse(split[1])]);
    }

    List<dynamic> distances = [];
    for (var i = 0; i < hash.length; i++) {
      distances.add([]);
      for (var j = 0; j < hash.length; j++) {
        distances[i].add(double.infinity);
      }
    }

    List<dynamic> predecessors = [];
    for (var i = 0; i < hash.length; i++) {
      predecessors.add([]);
      for (var j = 0; j < hash.length; j++) {
        predecessors[i].add(null);
      }
    }

    for (var i = 0; i < hash.length; i++) {
      for (var j = 0; j < hash.length; j++) {
        if (i == j) {
          distances[j][j] = 0;
        } else {
          if (graph["${hash[i][0]}, ${hash[i][1]}"] != []) {
            for (var item in graph["${hash[i][0]}, ${hash[i][1]}"]) {
              int index = hash.indexWhere(
                  (element) => element[0] == item[0] && element[1] == item[1]);
              distances[i][index] = item[2];
              predecessors[i][index] = i;
            }
          }
          if (graph["${hash[j][0]}, ${hash[j][1]}"] != []) {
            for (var item in graph["${hash[j][0]}, ${hash[j][1]}"]) {
              int index = hash.indexWhere(
                  (element) => element[0] == item[0] && element[1] == item[1]);
              distances[index][j] = item[2];
              predecessors[index][j] = index;
            }
          }
        }
      }
    }

    return [distances, predecessors, hash];
  }

  static compute() async {
    var input = await initializer();
    var result = calculator(input[0], input[1]);

    for (var i = 0; i < result[0].length; i++) {
      for (var j = 0; j < result[0][i].length; j++) {
        if (result[0][i][j] == double.infinity) {
          result[0][i][j] = null;
        }
      }
    }

    for (var i = 0; i < result[1].length; i++) {
      for (var j = 0; j < result[1][i].length; j++) {
        if (result[1][i][j] == -1) {
          result[1][i][j] = null;
        }
      }
    }

    FileManager.writeToFile("predecessors.json", result[1]);
    FileManager.writeToFile("distances.json", result[0]);
    FileManager.writeToFile("hash.json", input[2]);
  }
}
