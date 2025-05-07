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

  /// Get the sub-inventory of [resultCommand] for each [fields] based on [method].
  List<dynamic> getByMethod(
    String method,
    List<dynamic> fields,
    Map<String, dynamic> resultCommand,
  ) {
    final resultCommandData;
    late dynamic mainOptions;

    if (method == "TBLE" || method == "REGX") {
      resultCommandData = this.getResultCommandData(resultCommand, true);
      mainOptions = resultCommandData['mainOptions'];
    } else {
      resultCommandData = this.getResultCommandData(resultCommand, false);
    }

    final mainResult = resultCommandData['mainResult'];
    final mainResultValid = resultCommandData['mainResultValid'];
    List<dynamic> args = [];
    Map<String, dynamic> result;
    List<dynamic> subInventory = [];

    if (!mainResultValid) return subInventory;

    switch (method) {
      case "TBLE":
        args = this.formatArray(mainResult, mainOptions);
        break;

      case "JSON":
        args = [this.formatJson(mainResult)];
        break;

      case "REGX":
        args = formatRegx(mainResult, mainOptions);

      case "PTXT":
      case "GREP":
        args = mainResult.split("\n").toList();
        break;

      default:
        logger.error(this.runtimeType.toString(), "Méthode inconnue : $method");
        return subInventory;
    }

    for (var arg in args) {
      result = {};

      this.processFieldRetrival(method, fields, resultCommand, result, arg);
      if (result.isNotEmpty) subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// Extract the result and options from [resultCommand].
  Map<String, dynamic> getResultCommandData(
      Map<String, dynamic> resultCommand, bool needOptions) {
    dynamic mainResult = resultCommand['main']?['result'];
    dynamic mainOptions;

    if (needOptions) mainOptions = resultCommand['main']?['options'];

    bool mainResultValid = !(mainResult == null || mainResult.isEmpty);

    return {
      'mainResult': mainResult,
      if (needOptions) 'mainOptions': mainOptions,
      'mainResultValid': mainResultValid,
    };
  }

  void processFieldRetrival(
      String method, fields, resultCommand, result, dynamic arg) {
    dynamic retrivalValue;
    late bool condition;
    late dynamic function;

    fields.forEach((field) {
      switch (method) {
        case "TBLE":
          retrivalValue = field['retrival_value'] ?? "";
          condition = true;
          function =
              arg.containsKey(retrivalValue) ? arg[retrivalValue] : "null";
          break;

        case "JSON":
          condition = true;
          function = arg[field['retrival_value']];
          break;

        case "REGX":
          try {
            retrivalValue = RegExp(field['retrival_value']);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            retrivalValue = null;
          }

          dynamic match = retrivalValue.firstMatch(arg);
          condition = retrivalValue != null && retrivalValue.hasMatch(arg);
          function = match != null ? match.group(1) : "null";
          break;

        case "PTXT":
          try {
            retrivalValue = int.parse(field['retrival_value']);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            retrivalValue = 0;
          }

          condition = true;
          function = (retrivalValue > 0 && retrivalValue <= arg.length)
              ? arg[retrivalValue - 1]
              : "null";
          break;

        case "GREP":
          retrivalValue = field['retrival_value'] ?? "";
          condition = arg.contains(retrivalValue);
          function = arg
              .substring(arg.indexOf(retrivalValue) + retrivalValue.length + 1);
          break;

        default:
          logger.error(
              this.runtimeType.toString(), "Méthode inconnue : $method");
          break;
      }

      this.getSubInventoryResult(
          resultCommand, result, field, condition, function);
    });
  }

  /// Build sub-inventory data in [result] based on [field] and [resultCommand] with [condition] and [function].
  void getSubInventoryResult(
      Map<String, dynamic> resultCommand,
      Map<String, dynamic> result,
      dynamic field,
      bool condition,
      dynamic function) {
    if (resultCommand.containsKey(field['name'])) {
      result.putIfAbsent(
          field['name'],
          () => this.getResult(
                field['retrival_output'] ?? "null",
                resultCommand[field['name']]?['result'] ?? "null",
                field['retrival_value'] ?? "null",
              ));
    } else {
      if (condition) {
        result.putIfAbsent(
          field['name'],
          () => function,
        );
      }
    }
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

  /// Format [result] string to a list of json.
  List<Map<String, dynamic>> formatArray(
    String result,
    Map<String, dynamic>? options,
  ) {
    final parsedLists = this.getArrayHeaders(result);
    final resultRows = parsedLists['rows']!;
    final headersList = parsedLists['headers']!;
    final Valid = this.areListsValid(options, resultRows, headersList);
    final useIndex = Valid['useIndex']!;
    final listsValid = Valid['listsValid']!;
    final jsonResult = listsValid
        ? this.convertRowsToJson(resultRows, headersList, useIndex)
        : <Map<String, dynamic>>[];

    return jsonResult;
  }

  /// Extracts headers from the [result] string.
  Map<String, List<String>> getArrayHeaders(result) {
    try {
      List<String> resultRows = result.split("\n");
      List<String> headersList = resultRows.removeAt(0).split(RegExp(r'\s+'));

      return {
        'rows': resultRows,
        'headers': headersList,
      };
    } catch (e) {
      logger.error(this.runtimeType.toString(), e.toString());

      return {
        'rows': [],
        'headers': [],
      };
    }
  }

  /// Check the use of index based on [options].
  /// Check the validity of [resultRows] and [headersList].
  Map<String, bool> areListsValid(Map<String, dynamic>? options,
      List<String> resultRows, List<String> headersList) {
    bool useIndex = options != null && options['use_index'] == true;

    return {
      'useIndex': useIndex,
      'listsValid':
          resultRows.isNotEmpty && (headersList.isNotEmpty || !useIndex),
    };
  }

  /// Convert [resultRows] to json format.
  List<Map<String, dynamic>> convertRowsToJson(
      List<String> resultRows, List<String> headersList, bool useIndex) {
    List<String> resultFields;
    Map<String, dynamic> jsonLine;
    List<Map<String, dynamic>> jsonResult = [];

    resultRows.forEach((row) {
      resultFields = row.split(RegExp(r'\s+'));
      jsonLine = {};

      resultFields.asMap().forEach((i, field) {
        String key = useIndex ? headersList[i] : i.toString();

        jsonLine.putIfAbsent(key, () => field);
      });

      jsonResult.add(jsonLine);
    });

    return jsonResult;
  }

  /// Format [txt] to a valid json.
  Map<String, dynamic> formatJson(String txt) {
    Map<String, dynamic> result = {};
    List<String> lines = txt.split(RegExp(r'\r\n|\n|\r'));
    late String key;
    late String rawValue;
    late dynamic value;
    late int colonIndex;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line == "{" || line == "}") continue;

      colonIndex = line.indexOf(":");
      if (colonIndex == -1) continue;

      
      key = line.substring(0, colonIndex).trim();
      rawValue = line.substring(colonIndex + 1).trim();

      if (rawValue.toLowerCase() == 'true' || rawValue.toLowerCase() == 'false') {
        value = rawValue.toLowerCase() == 'true';
      } else if (int.tryParse(rawValue) != null) {
        value = int.parse(rawValue);
      } else {
        value = rawValue;
      }

      result[key] = value;
    }

    return result;
  }

  /// Format [mainResult] based on [mainOptions].
  List<String> formatRegx(mainResult, mainOptions) {
    RegExp? blockSeparator;
    final rawSeparator = mainOptions['separator'];
    bool multiple = mainOptions['multiple'] ?? false;
    late List<String> blocksList;

    if (rawSeparator is String && rawSeparator.trim().isNotEmpty)
      blockSeparator = RegExp(rawSeparator);

    blocksList = blockSeparator != null
        ? mainResult.split(blockSeparator)
        : blocksList = [mainResult];

    if (multiple)
      blocksList = blocksList.expand((block) => block.split('\n')).toList();

    return blocksList;
  }
}