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
import 'package:ocs_agent/core/inventory/windows/commands.dart';

/// Format command result by type for Windows.
class WindowsFormat {
  late Logger logger;
  late WindowsCommand windowsCommand;

  /// Constructor.
  WindowsFormat(this.logger, this.windowsCommand);

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByArray(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    List<Map<String, dynamic>> result = this.formatArray(
        resultCommand['main']['result'], resultCommand['main']['options']);
    List<dynamic> inventory = [];

    result.forEach((element) {
      Map<String, dynamic> subInventory = new Map();

      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          subInventory.putIfAbsent(
              field['name'],
              () => this.getResult(
                  field['retrival_output'],
                  resultCommand[field['name']]['result'],
                  field['retrival_value']));
        } else {
          String index = field["retrival_value"];

          if (element.containsKey(index)) {
            subInventory.putIfAbsent(field['name'], () => element[index]);
          } else {
            subInventory.putIfAbsent(field['name'], () => "null");
          }
        }
      }
      inventory.add(subInventory);
    });
    return inventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByJson(
      List<dynamic> fields, Map<String, dynamic> resultCommand) {
    var fieldsOver = fields.where((element) => element["override_target"]);
    Map<String, dynamic> json = {};
    List<dynamic> subInventory = [];
    late Map<String, dynamic> result;

    resultCommand.keys.forEach((element) {
      try {
        Map<String, dynamic>? rawOptions = resultCommand[element]['options'];

        if (rawOptions != null &&
            rawOptions.containsKey('need_format') &&
            !rawOptions['need_format']) {
          json[element] = jsonDecode(resultCommand[element]['result']);
        } else {
          json[element] = this.formatJson(resultCommand[element]['result']);
        }
      } catch (e) {
        json[element] = null;
        logger.verbose(this.runtimeType.toString(),
            "Failed to parse JSON data for element '$element': ${e.toString()}");
      }
    });

    if (json["main"] != null) {
      if (json["main"] is List<dynamic>) {
        json["main"].forEach((element) {
          subInventory.add(extractResult(element, fields));
        });
      } else {
        subInventory.add(extractResult(json["main"], fields));
      }
    } else {
      result = {};
      fields.forEach((field) {
        result[field['name']] ??= null;
      });
      subInventory.add(result);
    }

    fieldsOver.forEach((fieldOver) {
      if (json[fieldOver["name"]] != null) {
        if (json[fieldOver["name"]] is List<dynamic>) {
          json[fieldOver["name"]].forEach((element) {
            result = {};
            if (element.containsKey(fieldOver["retrival_value"])) {
              // if (element[fieldOver["retrival_value"]] is String) {
              //   result.update(fieldOver['name'],
              //       (dynamic) => element[fieldOver['retrival_value']].trim());
              // } else {
              //   result.update(fieldOver['name'],
              //       (dynamic) => element[fieldOver['retrival_value']]);
              // }
              result.update(
                  fieldOver['name'],
                  (dynamic) =>
                      element[fieldOver['retrival_value']].toString().trim());
            } else {
              result.update(fieldOver['name'], (dynamic) => null);
            }
            subInventory.add(result);
          });
        } else {
          if (json[fieldOver["name"]]
              .containsKey(fieldOver["retrival_value"])) {
            // if (json[fieldOver["name"]][fieldOver["retrival_value"]]
            //     is String) {
            //   result.update(
            //       fieldOver['name'],
            //       (dynamic) => json[fieldOver["name"]]
            //               [fieldOver['retrival_value']]
            //           .trim());
            // } else {
            //   result.update(
            //       fieldOver['name'],
            //       (dynamic) =>
            //           json[fieldOver["name"]][fieldOver['retrival_value']]);
            // }
            result.update(
                fieldOver['name'],
                (dynamic) => json[fieldOver["name"]]
                        [fieldOver['retrival_value']]
                    .toString()
                    .trim());
          }
        }
      }
    });

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByPtxt(List<dynamic> fields, String resultCommand) {
    var txt = resultCommand.split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var field in fields) {
      int line = int.parse(field['retrival_value']);
      result.putIfAbsent(field['name'], () => txt[line - 1]);
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByRegx(List<dynamic> fields, String resultCommand) {
    var lines = resultCommand.split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var line in lines) {
      for (var field in fields) {
        var regex = RegExp(field['retrival_value']);
        if (regex.hasMatch(line)) {
          var match = regex.firstMatch(line);
          result.putIfAbsent(field['name'], () => match!.group(1));
        }
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByGrep(List<dynamic> fields, String resultCommand) {
    var lines = resultCommand.split("\n").toList();
    List<dynamic> subInventory = new List.empty(growable: true);
    Map<String, dynamic> result = new Map();

    for (var line in lines) {
      for (var field in fields) {
        String grep = field['retrival_value'];
        if (line.contains(grep)) {
          result.putIfAbsent(field['name'],
              () => line.substring(line.indexOf(grep) + grep.length + 1));
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

    String? headerLine;
    List<String>? listIndex;

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
      listIndex!.forEach((element) {
        int index = headerLine!.indexOf(element, max);
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
    String json = "{\r\n";

    var list = txt.split("\r");

    list.removeWhere((element) => element.trim().isEmpty);

    int n = 1;

    list.forEach((element) {
      element = element.trimLeft();
      var list2 = element.split(":");

      if (list2.asMap().containsKey(1)) {
        var key = list2[0].trim();
        var value = list2.sublist(1).join(":").trim();

        if (value.isEmpty) {
          value = key;
        }

        var sanitizedValue;
        if (value.toLowerCase() == 'true' || value.toLowerCase() == 'false') {
          sanitizedValue = value.toLowerCase();
        } else if (int.tryParse(value) != null) {
          sanitizedValue = value;
        } else {
          sanitizedValue = "\"" + value.replaceAll("\"", "\\\"") + "\"";
        }

        if (n < list.length - 1) {
          json += "\"$key\": $sanitizedValue,\r\n";
        } else {
          json += "\"$key\": $sanitizedValue\r\n";
        }
      }

      n++;
    });

    json += "}";

    return jsonDecode(json);
  }
}

Map<String, dynamic> extractResult(
    Map<String, dynamic> currentMain, List<dynamic> fields) {
  final result = <String, dynamic>{};

  fields.forEach((field) {
    final key = field['retrival_value'];
    if (currentMain.containsKey(key)) {
      result[field['name']] ??= currentMain[key].toString().trim();
    } else {
      result[field['name']] ??= null;
    }
  });

  return result;
}

