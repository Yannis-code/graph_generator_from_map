import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

Widget searchField(TextEditingController controller, List<String> data) {
  return TypeAheadField(
    direction: AxisDirection.up,
    textFieldConfiguration: TextFieldConfiguration(
        controller: controller,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            vertical: 15.0,
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30.0),
              borderSide: const BorderSide(width: 0.8)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30.0),
              borderSide: const BorderSide(
                width: 0.8,
              )),
          prefixIcon: const Icon(
            Icons.search,
            size: 30,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.cancel),
            onPressed: () => controller.text = "",
          ),
        )),
    suggestionsCallback: (String query) => searchSuggestion(data, query),
    itemBuilder: buildSuggestion,
    onSuggestionSelected: (String query) {
      controller.text = query;
    },
  );
}

List<String> searchSuggestion(List<String> data, String text) {
  List<String> suggestionList = [];
  if (data.isNotEmpty) {
    var extracted = extractAllSorted(query: text, choices: data);
    for (var i = 0; i < min(extracted.length, 5); i++) {
      suggestionList.add(data[extracted[i].index]);
    }
  }
  return suggestionList;
}

Widget buildSuggestion(BuildContext context, String query) {
  return ListTile(
    title: Text(query),
    leading: const Icon(Icons.search),
  );
}

bool checkValidity(String query, List<String> comparable) {
  return query ==
      comparable[extractOne(query: query, choices: comparable).index];
}
