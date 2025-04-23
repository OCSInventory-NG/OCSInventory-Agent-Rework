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
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    List<Map<String, dynamic>> result = [];
    List<dynamic> inventory = [];
    Map<String, dynamic> subInventory;

    var mainResult = resultCommand['main']?['result'];
    var mainOptions = resultCommand['main']?['options'];

    if (mainResult != null && mainOptions != null) {
      result = this.formatArray(mainResult, mainOptions);
    } else {
      logger.error(
        this.runtimeType.toString(),
        "Missing 'main.result' or 'main.options' in resultCommand.",
      );
    }

    if (result.isNotEmpty) {
      result.forEach((element) {
        subInventory = {};

        for (var field in fields) {
          if (resultCommand.containsKey(field['name'])) {
            subInventory.putIfAbsent(
              field['name'],
              () => this.getResult(
                field['retrival_output'] ?? "null",
                resultCommand[field['name']]?['result'] ?? "null",
                field['retrival_value'] ?? "null",
              ),
            );
          } else {
            String index;

            try {
              index = field['retrival_value'];
            } catch (e) {
              logger.error(this.runtimeType.toString(), e.toString());
              index = "";
            }

            subInventory.putIfAbsent(
              field['name'],
              () => element.containsKey(index) ? element[index] : "null",
            );
          }
        }

        inventory.add(subInventory);
      });
    }

    logger.verbose(this.runtimeType.toString(), inventory.toString());

    return inventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByJson(
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    var fieldsOver = fields.where((element) => element['override_target']);
    late Map<String, dynamic> result;
    Map<String, dynamic> json = {};
    List<dynamic> subInventory = [];

    resultCommand.keys.forEach((element) {
      try {
        // If need_format is true, format the json
        // If need_format is false or not present, return the json as is
        json[element] =
            (resultCommand[element]?['options']?['need_format'] ?? false)
                ? this.formatJson(resultCommand[element]['result'])
                : jsonDecode(resultCommand[element]['result']);
      } catch (e) {
        json[element] = null;
        logger.verbose(
          this.runtimeType.toString(),
          "Failed to parse JSON data for element '$element': ${e.toString()}",
        );
      }
    });

    if (json['main'] != null) {
      if (json['main'] is List<dynamic>) {
        json['main'].forEach((element) {
          result = extractResult(element, fields);
          subInventory.add(result);
        });
      } else {
        result = extractResult(json['main'], fields);
        subInventory.add(result);
      }
    } else {
      result = {};

      fields.forEach((field) {
        result.putIfAbsent(field['name'], () => null);
      });

      subInventory.add(result);
    }

    fieldsOver.forEach((fieldOver) {
      if (json[fieldOver['name']] != null &&
          json[fieldOver['name']] is List<dynamic>) {
        json[fieldOver['name']].forEach((element) {
          result = {};
          updateResult(element, fieldOver, result);

          if (element!.containsKey(fieldOver['retrival_value'])) {
            result.update(fieldOver['name'], (dynamic) => null);
          }

          subInventory.add(result);
        });
      } else {
        updateResult(json[fieldOver['name']], fieldOver, result);
      }
    });

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByPtxt(List<dynamic> fields, String resultCommand) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> txt = [];

    try {
      txt = resultCommand.split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    for (var field in fields) {
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

    subInventory.add(result);

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByRegx(List<dynamic> fields, String resultCommand) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> lines = [];

    try {
      lines = resultCommand.split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    if (lines.isNotEmpty) {
      for (var line in lines) {
        for (var field in fields) {
          var regex;

          try {
            regex = RegExp(field['retrival_value']);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            regex = null;
          }

          if (regex != null && regex.hasMatch(line)) {
            var match = regex.firstMatch(line);
            result.putIfAbsent(field['name'], () => match!.group(1));
          }
        }
      }
      subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// get result of [resultCommand] for each [fields].
  List<dynamic> getByGrep(List<dynamic> fields, String resultCommand) {
    List<dynamic> subInventory = [];
    Map<String, dynamic> result = {};
    List<String> lines = [];

    try {
      lines = resultCommand.split("\n").toList();
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    if (lines.isNotEmpty) {
      for (var line in lines) {
        for (var field in fields) {
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
              () => line.substring(line.indexOf(grep) + grep.length + 1),
            );
          }
        }
      }
      subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
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
        List<String> txt = [];
        int line;

        try {
          txt = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
        }

        try {
          line = int.parse(retrivalValue);
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          line = 0;
        }

        return (line > 0 && line <= txt.length) ? txt[line - 1] : "null";

      case "REGX":
        List<String> lines = [];
        RegExp? regex;

        try {
          lines = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
        }

        try {
          regex = RegExp(retrivalValue);
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
          regex = null;
        }

        if (lines.isNotEmpty) {
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
        }

        break;

      case "GREP":
        String grep = retrivalValue;
        List<String> lines = [];

        try {
          lines = result.split("\n").toList();
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
        }

        if (lines.isNotEmpty) {
          for (var line in lines) {
            if (line.contains(grep)) {
              return line.substring(line.indexOf(grep) + grep.length + 1);
            }
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
    List<String> list = [];
    String headerLine;
    List<String> listIndex = [];

    try {
      list = result.split("\n");
      headerLine = list.removeAt(0);
      listIndex = headerLine.split(" ");
      listIndex.removeWhere((element) => element.isEmpty);
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
      headerLine = "";
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
          var resultLine = [];

          try {
            resultLine = element.split(' ');
            resultLine.removeWhere((element2) => element2.isEmpty);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
          }

          int index = 0;
          if (resultLine.isNotEmpty) {
            resultLine.forEach((element) {
              lineJson.putIfAbsent(index.toString(), () => element);
              index++;
            });
          }
        }

        returnValue.add(lineJson);
      });
    }

    return returnValue;
  }

  /// format result [txt] to json.
  Map<String, dynamic> formatJson(String txt) {
    String json = "{\r\n";
    List<String> list = [];

    try {
      list = txt.split("\r");
      list.removeWhere((element) => element.isEmpty);
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }

    int n = 1;

    if (list.isNotEmpty) {
      list.forEach((element) {
        element = element.trimLeft();
        List<String> list2 = [];

        try {
          list2 = element.split(":");
        } catch (e) {
          logger.error(this.runtimeType.toString(), e.toString());
        }

        if (list2.isNotEmpty) {
          if (list2.asMap().containsKey(1)) {
            String key = list2[0].trim();
            String value = list2.sublist(1).join(":").trim();
            String sanitizedValue;

            if (value.isEmpty) {
              value = key;
            }

            if (value.toLowerCase() == 'true' ||
                value.toLowerCase() == 'false') {
              sanitizedValue = value.toLowerCase();
            } else if (int.tryParse(value) != null) {
              sanitizedValue = value;
            } else {
              sanitizedValue = "\"" + value.replaceAll("\"", "\\\"") + "\"";
            }

            json +=
                "\"" +
                key +
                "\": \"" +
                sanitizedValue +
                (n < list.length ? "\",\r\n" : "\"\r\n");
          }

          n++;
        }
      });
    }

    json += "}";

    return jsonDecode(json);
  }

  Map<String, dynamic> extractResult(
    Map<String, dynamic> currentMain,
    List<dynamic> fields,
  ) {
    Map<String, dynamic> result = {};

    fields.forEach((field) {
      String key;

      try {
        key = field['retrival_value'];
      } catch (e) {
        logger.error(this.runtimeType.toString(), e.toString());
        key = "";
      }

      result.putIfAbsent(
        field['name'],
        () =>
            currentMain.containsKey(key)
                ? currentMain[key].toString().trim()
                : null,
      );
    });

    return result;
  }

  void updateResult(
    Map<String, dynamic> currentMain,
    dynamic fieldOver,
    dynamic result,
  ) {
    try {
      if (currentMain.containsKey(fieldOver["retrival_value"])) {
        result.update(
          fieldOver['name'],
          (dynamic) =>
              currentMain[fieldOver['retrival_value']].toString().trim(),
        );
      }
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());
    }
  }
}
