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
import 'package:ocs_agent/core/inventory/commands.dart';
import 'package:ocs_agent/core/log.dart';

/// Format command result by type.
class Format {
  late Logger logger;
  late Commands commands;

  /// Constructor.
  Format(this.logger, this.commands);

  /// Get the sub-inventory of [resultCommand] for each [fields] based on [method].
  List<dynamic> getByMethod(
      String method, List<dynamic> fields, Map<String, dynamic> resultCommand,
      [String? commandLine]) {
    late final commandTarget;
    late dynamic refField;
    late bool fieldNameExists;
    late dynamic resultCommandData;
    late dynamic mainResult;
    late bool mainResultValid;
    late dynamic mainOptions;
    late List<dynamic> processedResults;
    List<dynamic> subInventory = [];
    late Map<String, dynamic> result;

    // For MacOS
    try {
      commandTarget = commandLine?.split(" ")[1];
    } catch (_) {
      commandTarget = null;
    }

    if (fields.isEmpty) {
      logger.warning(runtimeType.toString(), "No fields available");
      return subInventory;
    }

    refField = fields.firstWhere((f) => resultCommand.containsKey(f['name']),
        orElse: () => fields.first);

    fieldNameExists = resultCommand.containsKey(refField['name']);
    resultCommandData = this.getDataFromResultCommand(
        method, resultCommand, refField, fieldNameExists);
    mainResult = resultCommandData['mainResult'];
    mainResultValid = resultCommandData['mainResultValid'];
    mainOptions = resultCommandData['mainOptions'];

    if (!mainResultValid) {
      logger.warning(this.runtimeType.toString(),
          "No results to process: the input data is empty or malformed.");
      return subInventory;
    }

    processedResults =
        getProcessedResults(method, mainResult, mainOptions, commandTarget);

    for (var processedResult in processedResults) {
      result = {};

      this.processFieldRetrival(method, fields, resultCommand, fieldNameExists,
          processedResult, result);

      if (result.isNotEmpty) subInventory.add(result);
    }

    logger.verbose(this.runtimeType.toString(), subInventory.toString());

    return subInventory;
  }

  /// Extract the result and options from [resultCommand] with [method], [field] and [fieldNameExists].
  Map<String, dynamic> getDataFromResultCommand(String method,
      Map<String, dynamic> resultCommand, dynamic field, bool fieldNameExists) {
    late dynamic mainResult;
    late bool mainResultValid;
    late dynamic mainOptions;

    mainResult = fieldNameExists
        ? (resultCommand[field['name']]?['result'])
        : (resultCommand['main']?['result']);
    mainResultValid = !(mainResult == null || mainResult.isEmpty);
    mainOptions = (method == "TBLE" || method == "REGX")
        ? (resultCommand['main']?['options'])
        : null;

    return {
      'mainResult': mainResult,
      'mainResultValid': mainResultValid,
      'mainOptions': mainOptions,
    };
  }

  /// Process the [mainResult] based on [method], [mainOptions] and [commandTarget] for MacOS.
  List<dynamic> getProcessedResults(String method, dynamic mainResult,
      dynamic mainOptions, String? commandTarget) {
    List<dynamic> processedResults = [];

    switch (method) {
      case "TBLE":
        processedResults = this.formatArray(mainResult, mainOptions);
        break;

      case "JSON":
        try {
          if (commandTarget == null) {
            processedResults = [jsonDecode(mainResult)];
          } else {
            // If the OS is MacOS
            Map<String, dynamic> decodedResult = jsonDecode(mainResult);
            List<dynamic> targetResult = decodedResult[commandTarget];
            processedResults = targetResult.cast<Map<String, dynamic>>();
          }
        } catch (e) {
          logger.warning(
            this.runtimeType.toString(),
            "Skip due to invalid or malformed JSON.",
          );
        }
        break;

      case "REGX":
        processedResults = formatRegx(mainResult, mainOptions);

      case "PTXT":
      case "GREP":
        processedResults = mainResult.split("\n").toList();
        break;

      default:
        logger.warning(this.runtimeType.toString(), "Unknown method : $method");
    }

    return processedResults;
  }

  /// Process sub-inventory build based on [method], [fields], [resultCommand], [fieldNameExists], [processedResult] and [result] parameters.
  void processFieldRetrival(
      String method,
      dynamic fields,
      Map<String, dynamic> resultCommand,
      bool fieldNameExists,
      dynamic processedResult,
      Map<String, dynamic> result) {
    dynamic retrivalValue;
    late bool condition;
    late dynamic function;

    if (processedResult == null || processedResult.isEmpty) return;

    fields.forEach((field) {
      switch (method) {
        case "TBLE":
          retrivalValue = field['retrival_value'] ?? "";
          condition = true;
          function = processedResult[retrivalValue] ?? "null";
          break;

        case "JSON":
          condition = true;
          function = processedResult[field['retrival_value']] ?? "null";
          break;

        case "REGX":
          try {
            retrivalValue = RegExp(field['retrival_value']);
          } catch (e) {
            logger.error(this.runtimeType.toString(), e.toString());
            retrivalValue = null;
          }

          dynamic match = retrivalValue.firstMatch(processedResult);
          condition =
              retrivalValue != null && retrivalValue.hasMatch(processedResult);
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
          function =
              (retrivalValue > 0 && retrivalValue <= processedResult.length)
                  ? processedResult[retrivalValue - 1]
                  : "null";
          break;

        case "GREP":
          retrivalValue = field['retrival_value'] ?? "";
          condition = processedResult.contains(retrivalValue);

          final index = processedResult.indexOf(retrivalValue);
          final start = index + retrivalValue.length + 1;

          if (index == -1) {
            logger.warning(this.runtimeType.toString(),
                "Retrival value '$retrivalValue' not found in: $processedResult");
            return;
          }

          if (start >= processedResult.length) {
            logger.error(this.runtimeType.toString(),
                "Start index $start out of bounds for: $processedResult");
            return;
          }

          function = processedResult.substring(start);
          break;

        default:
          logger.warning(this.runtimeType.toString(), "Unknown method : $method");
          break;
      }

      if (fieldNameExists) condition = true;

      this.getSubInventoryResult(result, field, condition, function);
    });
  }

  /// Build sub-inventory data in [result] based on [field] and with [condition] and [function] parameters.
  void getSubInventoryResult(Map<String, dynamic> result, dynamic field,
      bool condition, dynamic function) {
    if (condition) {
      result.putIfAbsent(
        field['name'],
        () => function,
      );
    }
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
  Map<String, List<String>> getArrayHeaders(String result) {
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

  /// Format [mainResult] based on [mainOptions].
  List<String> formatRegx(dynamic mainResult, dynamic mainOptions) {
    RegExp? blockSeparator;
    final rawSeparator = mainOptions['separator'];
    if (mainOptions['multiple'] == "true") mainOptions['multiple'] = true;
    bool multiple = mainOptions['multiple'] ?? false;
    late List<String> blocksList;

    if (rawSeparator is String && rawSeparator.trim().isNotEmpty)
      blockSeparator = RegExp("(?=${rawSeparator})");

    blocksList = blockSeparator != null
        ? mainResult.split(blockSeparator)
        : [mainResult];

    if (multiple)
      blocksList = blocksList.expand((block) => block.split('\n')).toList();

    return blocksList;
  }
}
