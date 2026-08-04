// OCSInventory Agent
// Copyright (C) OCSInventory
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
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

// Core imports
import 'package:ocsinventory_agent/core/config.dart';
import 'package:ocsinventory_agent/core/log.dart';

/// Class for execute command.
class Commands {
  late Logger logger;
  late Config config;

  static const int defaultExecutionTimeout = 120;

  static const String timeoutError = "TIMEOUT";

  /// Constructor
  Commands(this.logger, this.config);

  int getExecutionTimeout() {
    final dynamic configuredTimeout =
        config.getInventoryConfig("execution_timeout");

    if (configuredTimeout is int && configuredTimeout > 0) {
      return configuredTimeout;
    }

    return defaultExecutionTimeout;
  }

  /// Process the given target based on the [method].
  Future<Map<String, Object>> processTarget(
      String method, String target, String section, String field) async {
    if (field != "") {
      field = " [$field]";
    }
    logger.debug(
      runtimeType.toString(),
      "[$section]$field Executing $method: '$target'",
    );

    final methodParameters = await getMethodParameters(method, target);
    final process = methodParameters['process'] as ProcessResult?;
    final commentSubject = methodParameters['commentSubject'] as String?;
    final Map<String, Object> processData = {};

    if (process == null) return processData;

    final int exitCode = process.exitCode;

    final String stdoutStr = _decodeBytes(process.stdout).trim();
    final String stderrStr = _decodeBytes(process.stderr).trim();

    final bool timedOut = stderrStr == timeoutError;

    processData["value"] = (exitCode == 0) ? stdoutStr : "";
    processData["status"] = (exitCode == 0);
    processData["error"] = stderrStr;

    if (!timedOut && stderrStr.isNotEmpty) {
      logger.error(
        runtimeType.toString(),
        "Executing ${commentSubject ?? 'target'} '$target' - Error: $stderrStr",
      );
    }

    if (!timedOut && stdoutStr.isEmpty) {
      logger.warning(
        runtimeType.toString(),
        "No output for ${commentSubject ?? 'target'} '$target'.",
      );
    }

    return processData;
  }

  /// Get the parameters based on [method] and [target].
  Future<Map<String, dynamic>> getMethodParameters(
      String method, String target) async {
    ProcessResult? process;
    String? executable;
    List<String>? commandArguments;
    late String commentSubject;

    switch (method) {
      case "BASH":
        executable = "bash";
        commandArguments = ["-c", target];
        commentSubject = "command";
        break;

      case "CMD":
        executable = "cmd.exe";
        commandArguments = ["/c", target];
        commentSubject = "command";
        break;

      case "PW":
        executable = "powershell.exe";
        commandArguments = [
          "-NoLogo",
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-Command",
          r"chcp 65001 > $null; "
              r"$OutputEncoding = New-Object System.Text.UTF8Encoding($false); "
              r"[Console]::OutputEncoding = $OutputEncoding; "
              r"$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'; "
              "$target"
        ];
        commentSubject = "command";
        break;

      case "FILE":
        executable = "cat";
        commandArguments = [target];
        commentSubject = "file";
        break;

      default:
        logger.error(
          runtimeType.toString(),
          "Unknown method : $method",
        );

        return {
          'process': null,
          'commentSubject': "",
        };
    }

    process = await executeTarget(target, executable!, commandArguments!);

    return {
      'process': process,
      'commentSubject': commentSubject,
    };
  }

  Future<ProcessResult?> executeTarget(
      String target, String executable, List<String> commandArguments) async {
    ProcessResult? process;
    final int timeoutSeconds = getExecutionTimeout();

    try {
      process = await Process.run(
        executable,
        commandArguments,
        stdoutEncoding: null,
        stderrEncoding: null,
      ).timeout(Duration(seconds: timeoutSeconds), onTimeout: () {
        logger.warning(
          runtimeType.toString(),
          "Command '$target' exceeded the execution timeout (${timeoutSeconds}s), aborting.",
        );

        return ProcessResult(0, -1, "", timeoutError);
      });
    } on ProcessException catch (e) {
      logger.warning(
        runtimeType.toString(),
        "This command or file '$target' could not be found : $e",
      );
    } catch (e) {
      logger.error(runtimeType.toString(), 'An error occurred : $e');
      process = null;
    }

    return process;
  }

  /// Execute or read [target] in terms of [method].
  Future<String> getTargetResult(
      String method, String target, String section, String field) async {
    return (await processTarget(method, target, section, field))["value"]
        .toString();
  }

  // Dynamic decode output
  String _decodeBytes(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;

    if (data is List<int>) {
      final bytes = Uint8List.fromList(data);

      // BOM UTF-8: EF BB BF
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        return utf8.decode(bytes.sublist(3), allowMalformed: true);
      }

      // BOM UTF-16LE: FF FE
      if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        final b = bytes.sublist(2);
        final bd = ByteData.sublistView(b);
        final codeUnits = <int>[];
        for (var i = 0; i + 1 < b.length; i += 2) {
          codeUnits.add(bd.getUint16(i, Endian.little));
        }
        return String.fromCharCodes(codeUnits);
      }

      // BOM UTF-16BE: FE FF
      if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        final b = bytes.sublist(2);
        final bd = ByteData.sublistView(b);
        final codeUnits = <int>[];
        for (var i = 0; i + 1 < b.length; i += 2) {
          codeUnits.add(bd.getUint16(i, Endian.big));
        }
        return String.fromCharCodes(codeUnits);
      }

      // try UTF-8 else Latin-1
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return latin1.decode(bytes, allowInvalid: true);
      }
    }

    return data.toString();
  }
}
