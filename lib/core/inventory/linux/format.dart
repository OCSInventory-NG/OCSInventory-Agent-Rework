// OCSInventory Agent
// Copyright (C) OCSInventory-NG
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// External package imports
import 'dart:convert';

// Core imports
import 'package:ocs_agent/core/log.dart';
import 'package:ocs_agent/core/inventory/linux/commands.dart';

/// Format command result by type for Linux.
class LinuxFormat {
  late Logger logger;
  late LinuxCommand linuxCommand;

  /// Constructor.
  LinuxFormat(Logger logger, LinuxCommand linuxCommand) {
    this.logger = logger;
    this.linuxCommand = linuxCommand;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByArray(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    List<Map<String, dynamic>> arrayResult = this.formatArray(
        resultCommand['main']['result'], resultCommand['main']['options']);
    List<dynamic> subinventory = new List.empty(growable: true);
    Map<String, dynamic> result;

    arrayResult.forEach((element) {
      result = new Map();
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          result.putIfAbsent(
              field['name'],
              () => this.getResult(
                  field['retrival_output'],
                  resultCommand[field['name']]['result'],
                  field['retrival_value']));
        } else {
          String index = field["retrival_value"];

          if (element.containsKey(index)) {
            result.putIfAbsent(field['name'], () => element[index]);
          } else {
            result.putIfAbsent(field['name'], () => "null");
          }
        }
      }
      subinventory.add(result);
    });

    logger.verbose(this.runtimeType.toString(), subinventory.toString());

    return subinventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByJson(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    var json = this.formatJson(resultCommand['main']['result']);
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var field in fields) {
      if (resultCommand.containsKey(field['name'])) {
        result.putIfAbsent(
            field['name'],
            () => this.getResult(
                field['retrival_output'],
                resultCommand[field['name']]['result'],
                field['retrival_value']));
      } else {
        result.putIfAbsent(field['name'], () => json[field['retrival_value']]);
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  Future<List<dynamic>> getByPtxt(
      List<dynamic> fields, Map<String, dynamic> resultCommand) async {
    var txt = resultCommand['main']['result'].split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var field in fields) {
      if (resultCommand.containsKey(field['name'])) {
        result.putIfAbsent(
            field['name'],
            () => this.getResult(
                field['retrival_output'],
                resultCommand[field['name']]['result'],
                field['retrival_value']));
      } else {
        int line = int.parse(field['retrival_value']);
        result.putIfAbsent(field['name'], () => txt[line - 1]);
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByRegx(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    var lines = resultCommand['main']['result'].split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    bool multiple = false;
    var separator;
    bool haveSeparator = false;
    bool separate = false;

    if (resultCommand['main']['options'] != null &&
        resultCommand['main']['options'].containsKey('multiple') &&
        resultCommand['main']['options']['multiple']) {
      multiple = true;
    }
    if (resultCommand['main']['options'] != null &&
        resultCommand['main']['options'].containsKey('separator')) {
      separator = RegExp(resultCommand['main']['options']['separator']);
      haveSeparator = true;
    }

    int x = 1;
    for (var line in lines) {
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          result.putIfAbsent(
              field['name'],
              () => this.getResult(
                  field['retrival_output'],
                  resultCommand[field['name']]['result'],
                  field['retrival_value']));
        } else {
          var regex = RegExp(field['retrival_value']);
          if (regex.hasMatch(line)) {
            var match = regex.firstMatch(line);
            result.putIfAbsent(field['name'], () => match!.group(1));
          }
        }
      }
      if (multiple) {
        if ((separator != null && separator.hasMatch(line) ||
            x == lines.length)) {
          separate = true;
        }
        if (haveSeparator) {
          if (separate) {
            if (result.isNotEmpty) {
              subInventory.add(result);
              result = new Map();
            }
            separate = false;
          }
        } else {
          if (result.isNotEmpty) {
            subInventory.add(result);
            result = new Map();
          }
        }
      }
      x++;
    }
    if (!multiple && result.isNotEmpty) {
        subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByGrep(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    var lines = resultCommand['main']['result'].split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var line in lines) {
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          result.putIfAbsent(
              field['name'],
              () => this.getResult(
                  field['retrival_output'],
                  resultCommand[field['name']]['result'],
                  field['retrival_value']));
        } else {
          var grep = field['retrival_value'];
          if (line.contains(grep)) {
            result.putIfAbsent(field['name'],
                () => line.substring(line.indexOf(grep) + grep.length + 1));
          }
        }
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  String? getResult(String type, String result, retrivalValue) {
    switch (type) {
      case "JSON":
        var json = this.formatJson(result);
        return json[retrivalValue];

      case "PTXT":
        var txt = result.split("\n").toList();
        int line = int.parse(retrivalValue);
        return txt[line - 1];

      case "REGX":
        var lines = result.split("\n").toList();
        var regex = RegExp(retrivalValue);
        for (var line in lines) {
          if (regex.hasMatch(line)) {
            var match = regex.firstMatch(line);
            return match!.group(1);
          }
        }

        break;
      case "GREP":
        var lines = result.split("\n").toList();
        String grep = retrivalValue;
        for (var line in lines) {
          if (line.contains(grep)) {
            return line.substring(line.indexOf(grep) + grep.length + 1);
          }
        }

        break;
      default:
        return "null";
    }
    return null;
  }

  /// Format [result] text to a list of json.
  List<Map<String, dynamic>> formatArray(
      String result, Map<String, dynamic> options) {
    List<String> list = result.split("\n");

    late String headerLine;
    late List<String> listIndex;

    if (options.containsKey("use_index") && options['use_index']) {
      headerLine = list[0];
      list.removeAt(0);
      listIndex = headerLine.split(" ");
      listIndex.removeWhere((element) => element == "");
    } else {
      list.removeAt(0);
    }

    //print(headerLine);
    Map<String, int> mapIndex = new Map<String, int>();
    List<int> listLines = [];
    List<Map<String, dynamic>> returnValue = [];

    if (options.containsKey("use_index") && options['use_index']) {
      int max = 0;
      listIndex.forEach((element) {
        int index = headerLine.indexOf(element, max);
        max = index;
        mapIndex.putIfAbsent(element, () => index);
        listLines.add(index);
      });

      list.forEach((element) {
        Map<String, dynamic> lineJson = new Map<String, dynamic>();
        mapIndex.forEach((key, value) {
          int start = listLines[listLines.indexOf(value)];
          int? after;
          if (listLines.indexOf(value) + 1 >= listLines.length) {
            after = null;
          } else {
            after = listLines[listLines.indexOf(value) + 1];
          }
          String lineValue = element.substring(start, after);
          lineValue = lineValue.replaceAll(new RegExp(r'[\s]+$'), '');

          lineJson.putIfAbsent(key, () => lineValue);
        });
        returnValue.add(lineJson);
      });
    } else {
      list.forEach((element) {
        Map<String, dynamic> lineJson = new Map<String, dynamic>();
        var test = element.split(' ');
        test.removeWhere((element2) => element2 == "");
        int index = 0;
        test.forEach((element) {
          lineJson.putIfAbsent(index.toString(), () => element);
          index++;
        });
        returnValue.add(lineJson);
      });
    }

    return returnValue;
  }

  /// format result [txt] to json.
  Map<String, dynamic> formatJson(String txt) {
    String json = "{\n";

    var list = txt.split("\n");
    list.removeWhere((element) => element == "");
    list.removeWhere((element) => element == "{");
    list.removeWhere((element) => element == "}");

    int n = 1;

    list.forEach((element) {
      //element = element.replaceAll(new RegExp(r"^ *"), '');
      element = element.replaceAll(new RegExp(r"^\s*"), '');

      var list2 = element.split(":");

      if (list2.asMap().containsKey(1)) {
        //list2[1] = list2[1].replaceAll(new RegExp(r"^ *"), '');
        list2[1] = list2[1].replaceAll(new RegExp(r"^\s*"), '');
        list2[1] = list2[1].replaceAll(new RegExp(r"\s*$"), '');

        String sep1;
        String sep2;

        if (list2[0].contains("\"")) {
          sep1 = "";
        } else {
          sep1 = "\"";
        }

        if (list2[1].contains("\"")) {
          sep2 = "";
        } else {
          sep2 = "\"";
        }

        if (n < list.length) {
          json += sep1 + list2[0] + "$sep1: $sep2" + list2[1] + "$sep2,\n";
        } else {
          json += sep1 + list2[0] + "$sep1: $sep2" + list2[1] + "$sep2\n";
        }
      }
      n++;
    });
    json += "}";

    return jsonDecode(json);
  }
}
