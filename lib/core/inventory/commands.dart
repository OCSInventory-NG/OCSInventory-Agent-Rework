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
import 'dart:io';

// Core imports
import 'package:ocs_agent/core/log.dart';

/// Class for execute command.
class Commands {
  late Logger logger;

  /// Constructor
  Commands(this.logger);

  /// Process the given target based on the [method].
  Future<Map<String, Object>> processTarget(
      String method, String target) async {
    final methodParameters = await getMethodParameters(method, target);
    final process = methodParameters['process'];
    final commentSubject = methodParameters['commentSubject'];
    Map<String, Object> processData = {};

    if (process == null) return processData;

    int exitCode = process.exitCode;
    String stdout = process.stdout.toString().trim();
    String stderr = process.stderr.toString().trim();

    processData["value"] = (exitCode == 0) ? stdout : "";
    processData["status"] = (exitCode == 0);
    processData["error"] = stderr;

    logger.verbose(
        this.runtimeType.toString(), "Executed $commentSubject: '$target'");

    if (stderr.isNotEmpty)
      logger.error(this.runtimeType.toString(),
          "Executing $commentSubject '$target' - Error: ${stderr}");

    if (stdout.isEmpty)
      logger.warning(this.runtimeType.toString(),
          "No output for $commentSubject '$target'.");

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
          "-Command",
          "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $target"
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

    process = await executeTarget(target, executable, commandArguments);

    return {
      'process': process,
      'commentSubject': commentSubject,
    };
  }

  // Exécution unifiée avec gestion des erreurs
  Future<ProcessResult?> executeTarget(
      String target, String executable, List<String> commandArguments) async {
    ProcessResult? process;

    try {
      process = await Process.run(executable, commandArguments);
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
  Future<String> getResult(String method, String target) async {
    return (await this.processTarget(method, target))["value"].toString();
  }
}
