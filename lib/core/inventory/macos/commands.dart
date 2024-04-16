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

import 'dart:io';
import 'package:ocs_agent/core/log.dart';

/// Class for execute command on Mac.
class MacOSCommand {
  Logger logger = Logger();

  /// Execute [commandLine] to Shell.
  Future<String> commandShell(String commandLine, bool normalization) async {
    List<String> args = commandLine.split(" ");
    String command = args[0];
    args.removeAt(0);
    if (args.isEmpty) {
      args = [];
    }

    String processValue = "";
    try {
      // Attempt to run the command
      var process = await Process.run(command, args);
      if (normalization) {
        processValue = await process.stdout.toString().trim();
      } else {
        processValue = await process.stdout.toString();
      }

      if (process.exitCode != 0) {
        processValue = "";
        logger.error("Executing command '$commandLine' - ${process.stderr}");
      } else {
        logger.verbose("Command executed successfully: $commandLine");
      }
    } on ProcessException catch (e) {
      // Handle the specific error
      logger.error("This command '$command' could not be found : ${e}");
    } catch (e) {
      // Handle other errors
      logger.error('An error occurred : $e');
    }

    return processValue;
  }
}
