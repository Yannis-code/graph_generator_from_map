import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';

class FileManager {
  static Future<String> getLocalPath() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    print(applicationDirectory.path);

    return applicationDirectory.path;
  }

  static Future<File> getLocalFile() async {
    final path = await getLocalPath();

    return File('$path/outputGraph.json');
  }

  static Future<void> writeToFile(Map<dynamic, dynamic> jsonToSave) async {
    File F = await getLocalFile();

    // Write the file
    String text = json.encode(jsonToSave);
    File result = await F.writeAsString('$text');
    print("Writting Done!");
  }

  static Future<Map<dynamic, dynamic>> loadFromFile() async {
    File F = await getLocalFile();

    String text = await F.readAsString();
    Map<dynamic, dynamic> map = json.decode(text);
    print("Reading Done!");
    return map;
  }
}
