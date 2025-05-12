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

/// Class for execute command on linux.
class LinuxCommand {
  late Logger logger;

  /// Constructor
  LinuxCommand(this.logger);

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

    if (method == "BASH") processData["error"] = (exitCode == 0) ? "" : stderr;

    if (stdout.isEmpty)
      logger.error(this.runtimeType.toString(),
          "No output for $commentSubject '$target'.");

    logger.verbose(this.runtimeType.toString(),
        "Executed $commentSubject: '$target'");

    if (stderr.isNotEmpty)
      logger.error(this.runtimeType.toString(),
          "Executing $commentSubject '$target' - Error: ${stderr}");

    return processData;
  }

  /// Get the parameters based on [method] and [target].
  Future<Map<String, dynamic>> getMethodParameters(
      String method, String target) async {
    late ProcessResult? process;
    late String commentSubject;

    switch (method) {
      case "BASH":
        try {
          process = await Process.run('bash', ['-c', target]);
        } on ProcessException catch (e) {
          logger.error(this.runtimeType.toString(),
              "This command '$target' could not be found : $e");
        } catch (e) {
          logger.error(this.runtimeType.toString(), 'An error occurred : $e');
        }

        commentSubject = "command";
        break;

      case "FILE":
        try {
          process = await Process.run("cat", [target]);
        } on ProcessException catch (e) {
          logger.error(this.runtimeType.toString(),
              "This file '$target' could not be found : $e");
        } catch (e) {
          logger.error(this.runtimeType.toString(), 'An error occurred : $e');
        }

        commentSubject = "file";
        break;

      default:
        logger.error(this.runtimeType.toString(), "Unknown method : $method");

        process = null;
        commentSubject = "";
        break;
    }

    return {
      'process': process,
      'commentSubject': commentSubject,
    };
  }

  /// Execute or read [target] in terms of [method].
  Future<String?> getResult(String method, String target) async {
    return (await this.processTarget(method, target))["value"]
        .toString();
  }
}
