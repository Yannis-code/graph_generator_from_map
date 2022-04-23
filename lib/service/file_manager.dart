import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'dart:convert';

class FileManager {
  /// Return the path of the application
  static Future<String> getLocalPath() async {
    final applicationDirectory = await getApplicationDocumentsDirectory();
    String path = join(applicationDirectory.path, "generated");

    return path;
  }

  static Future<File> getLocalFile(String file) async {
    final path = await getLocalPath();

    return File('$path/$file');
  }

  static Future<void> writeToFile(String file, dynamic jsonToSave) async {
    File F = await getLocalFile(file);

    // Write the file
    String text = json.encode(jsonToSave);
    await F.writeAsString(text);
    debugPrint("Saved: $file");
  }

  static Future<dynamic> loadFromFile(String file) async {
    File F = await getLocalFile(file);

    String text = await F.readAsString();
    dynamic map = json.decode(text);
    debugPrint("Opened: $file");
    return map;
  }
}
