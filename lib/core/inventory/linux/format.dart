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
  LinuxFormat(this.logger, this.linuxCommand);

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByArray(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    List<Map<String, dynamic>> arrayResult = [];
    List<dynamic> subinventory = [];
    Map<String, dynamic> result;

    var mainResult = resultCommand['main']?['result'];
    var mainOptions = resultCommand['main']?['options'];

    if (mainResult != null && mainOptions != null) {
      arrayResult = this.formatArray(mainResult, mainOptions);
    } else {
      logger.error(
        this.runtimeType.toString(),
        "Missing 'main.result' or 'main.options' in resultCommand.",
      );
    }

    if (arrayResult.isNotEmpty) {
      arrayResult.forEach((element) {
        result = {};
        for (var field in fields) {
          if (resultCommand.containsKey(field['name'])) {
            extractResultsFromCommand(result, field, resultCommand);
          } else {
            String index;

            try {
              index = field["retrival_value"];
            } catch (e) {
              logger.error(this.runtimeType.toString(), e.toString());
              index = "";
            }

            result.putIfAbsent(
              field['name'],
              () => element.containsKey(index) ? element[index] : "null",
            );
          }
        }

        subinventory.add(result);
      });
    }

    logger.verbose(this.runtimeType.toString(), subinventory.toString());

    return subinventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByJson(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    Map<String, dynamic> json = {};
    var mainResult = resultCommand['main']?['result'];

    if (mainResult != null) {
      json = this.formatJson(mainResult);
    } else {
      logger.error(
        this.runtimeType.toString(),
        "Missing 'main.result' in resultCommand.",
      );
    }

    if (json.isNotEmpty) {
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          extractResultsFromCommand(result, field, resultCommand);
        } else {
          try {
            result.putIfAbsent(
              field['name'],
              () => json[field['retrival_value']],
            );
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            result.putIfAbsent(field['name'], () => "null");
          }
        }
      }

      subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  Future<List<dynamic>> getByPtxt(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) async {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> txt = [];

    try {
      txt = resultCommand['main']['result'].split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    for (var field in fields) {
      if (resultCommand.containsKey(field['name'])) {
        extractResultsFromCommand(result, field, resultCommand);
      } else {
        int line;

        try {
          line = int.parse(field['retrival_value']);
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          line = 0;
        }

        result.putIfAbsent(
          field['name'],
          () => (line > 0 && line <= txt.length) ? txt[line - 1] : "null",
        );
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByRegx(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> lines = [];

    try {
      lines = resultCommand['main']['result'].split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    bool multiple = resultCommand['main']?['options']?['multiple'] ?? false;
    bool separate;
    RegExp? separator;

    try {
      separator =
          resultCommand['main']?['options']?['separator'] != null
              ? RegExp(resultCommand['main']['options']['separator'])
              : null;
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
      separator = null;
    }

    bool haveSeparator = separator != null;

    int x = 1;
    for (var line in lines) {
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          extractResultsFromCommand(result, field, resultCommand);
        } else {
          RegExp? regex;

          try {
            regex = RegExp(field['retrival_value']);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            regex = null;
          }

          if (regex != null && regex.hasMatch(line)) {
            var match;

            try {
              match = regex.firstMatch(line);
            } catch (e) {
              logger.error(this.runtimeType.toString(), e.toString());
              match = null;
            }

            result.putIfAbsent(field['name'], () => match!.group(1));
          }
        }
      }

      separate =
          haveSeparator && (separator.hasMatch(line) || x == lines.length);

      if (multiple) {
        if (separate || !haveSeparator) {
          if (result.isNotEmpty) {
            subInventory.add(result);
            result = {};
          }
        }
      } else {
        subInventory.add(result);
      }

      x++;
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByGrep(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> lines;

    try {
      lines = resultCommand['main']['result'].split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
      lines = [];
    }

    for (var line in lines) {
      for (var field in fields) {
        if (resultCommand.containsKey(field['name'])) {
          extractResultsFromCommand(result, field, resultCommand);
        } else {
          String grep;

          try {
            grep = field['retrival_value'];
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            grep = "";
          }

          if (line.contains(grep)) {
            result.putIfAbsent(
              field['name'],
              () =>
                  line.contains(grep)
                      ? line.substring(line.indexOf(grep) + grep.length + 1)
                      : "null",
            );
          }
        }
      }
    }
    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  void extractResultsFromCommand(
    Map<String, dynamic> result,
    dynamic field,
    Map<String, dynamic> resultCommand,
  ) {
    result.putIfAbsent(
      field['name'],
      () => this.getResult(
        field['retrival_output'] ?? "null",
        resultCommand[field['name']]?['result'] ?? "null",
        field['retrival_value'] ?? "null",
      ),
    );
  }

  String? getResult(String type, String result, retrivalValue) {
    switch (type) {
      case "JSON":
        if (result.isNotEmpty) {
          var json = this.formatJson(result);
          return json[retrivalValue];
        }

        return "null";

      case "PTXT":
        List<String> txt;
        int line;

        try {
          txt = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          txt = [];
        }

        try {
          line = int.parse(retrivalValue);
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          line = 0;
        }

        return (line > 0 && line <= txt.length) ? txt[line - 1] : "null";

      case "REGX":
        List<String> lines;
        RegExp? regex;

        try {
          lines = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          lines = [];
        }

        try {
          regex = RegExp(retrivalValue);
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          regex = null;
        }

        for (var line in lines) {
          if (regex != null && regex.hasMatch(line)) {
            var match;

            try {
              match = regex.firstMatch(line);
            } catch (e) {
              logger.error(this.runtimeType.toString(), e.toString());
              match = null;
            }

            return match != null ? match.group(1) : "null";
          }
        }

        break;

      case "GREP":
        String grep = retrivalValue;
        List<String> lines;

        try {
          lines = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          lines = [];
        }

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
    String result,
    Map<String, dynamic> options,
  ) {
    List<Map<String, dynamic>> returnValue = [];
    List<String> list;
    String headerLine;
    List<String> listIndex;

    try {
      list = result.split("\n");
      headerLine = list.removeAt(0);
      listIndex = headerLine.split(" ");
      listIndex.removeWhere((element) => element.isEmpty);
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
      list = [];
      headerLine = "";
      listIndex = [];
    }

    Map<String, int> mapIndex = {};
    List<int> listLines = [];
    int max = 0;

    if (listIndex.isNotEmpty) {
      listIndex.forEach((element) {
        int index = headerLine.indexOf(element, max);
        max = index;
        mapIndex.putIfAbsent(element, () => index);
        listLines.add(index);
      });
    }

    if (list.isNotEmpty) {
      list.forEach((element) {
        Map<String, dynamic> lineJson = {};
        if (options.containsKey("use_index") && options['use_index']) {
          mapIndex.forEach((key, value) {
            int start = listLines[listLines.indexOf(value)];
            int? after =
                listLines.indexOf(value) + 1 >= listLines.length
                    ? null
                    : listLines[listLines.indexOf(value) + 1];

            String lineValue = element.substring(start, after).trimRight();
            lineJson.putIfAbsent(key, () => lineValue);
          });
        } else {
          var resultLine = element.split(' ');
          resultLine.removeWhere((element2) => element2.isEmpty);

          int index = 0;
          resultLine.forEach((element) {
            lineJson.putIfAbsent(index.toString(), () => element);
            index++;
          });
        }

        returnValue.add(lineJson);
      });
    }

    return returnValue;
  }

  /// format result [txt] to json.
  Map<String, dynamic> formatJson(String txt) {
    String json = "{\n";
    List<String> list = [];

    try {
      list = txt.split("\n");
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    if (list.isNotEmpty) {
      list.removeWhere(
        (element) => element.isEmpty || element == "{" || element == "}",
      );
    }

    int n = 1;

    if (list.isNotEmpty) {
      list.forEach((element) {
        element = element.trimLeft();
        List<String> list2;

        try {
          list2 = element.split(":");
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          list2 = [];
        }

        if (list2.isNotEmpty) {
          if (list2.asMap().containsKey(1)) {
            list2[1] = list2[1].trim();

            String key = list2[0].contains("\"") ? "" : "\"";
            String value = list2[1].contains("\"") ? "" : "\"";

            json +=
                key +
                list2[0] +
                "$key: $value" +
                list2[1] +
                "$value" +
                (n < list.length ? ",\n" : "\n");
          }
        }

        n++;
      });
    }

    json += "}";

    return jsonDecode(json);
  }
}
