import 'dart:convert';

import 'package:ocs_agent/core/inventory/macos/commands.dart';

class MacOSFormat {
  MacOSCommand macosCommand;

  MacOSFormat() {
    this.macosCommand = new MacOSCommand();
  }

  Future<String> getbyArray(String command, String indexString) async {
    return null;
  }

  Future<String> getbyJson(String command, String key) async {
    return null;
  }

  Future<String> getbyPtxt(String command, String lineString) async {
    return null;
  }

  Map<String, dynamic> formatJson(String txt) {
    String json = "{\n";

    var list = txt.split("\n");
    list.removeWhere((element) => element == "");

    int n = 1;

    list.forEach((element) {
      //element = element.replaceAll(new RegExp(r"^ *"), '');
      element = element.replaceAll(new RegExp(r"^\s*"), '');

      var list2 = element.split(":");

      if (list2.asMap().containsKey(1)) {
        //list2[1] = list2[1].replaceAll(new RegExp(r"^ *"), '');
        list2[1] = list2[1].replaceAll(new RegExp(r"^\s*"), '');

        if (n < list.length) {
          json += "\"" + list2[0] + "\": \"" + list2[1] + "\",\n";
        } else {
          json += "\"" + list2[0] + "\": \"" + list2[1] + "\"\n";
        }
      }
      n++;
    });
    json += "}";

    return jsonDecode(json);
  }
}
