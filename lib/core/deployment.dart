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

import 'dart:convert';
import 'dart:io';
import 'package:sprintf/sprintf.dart';

import 'package:ocs_agent/core/config.dart';
import 'package:ocs_agent/core/log.dart';

import 'package:ocs_agent/core/common/http_utils.dart';

import 'package:ocs_agent/core/inventory/linux/commands.dart';
import 'package:ocs_agent/core/inventory/macos/commands.dart';
import 'package:ocs_agent/core/inventory/windows/commands.dart';

class Deployment {
  // Modules
  late Config config;
  late Logger logger;

  // Utilities
  late HTTPUtils httpUtils;

// Other variable used by the class
  late var url;

  late List<dynamic> results;
  late Map<int, dynamic> actions;

  /// Constructor.
  Deployment() {
    // Modules init
    config = Config();
    logger = Logger();

    // Utilities init
    httpUtils = HTTPUtils();

    // Other variable init
    url = config.getInventoryConfig("url");
    actions = Map();
  }

  /// Check if there is packages to download.
  Future<bool> checkDownload(int assetID) async {
    logger.info("Enabling deployment module...");

    // API call: Check if there is assigned packages
    var response = await httpUtils.get(
        "checkDownload",
        Uri.parse(url + "/deployment/results/?asset=$assetID&status=0"),
        httpUtils.getHeader(config));
    // VERBOSE: show result of the query in verbose mode
    logger.verbose(response["message"]);

    if (response["status_code"] == 200 &&
        jsonDecode(response["body"]).isNotEmpty) {
      logger.info("Assigned packages found!");

      // Get the list of assigned packages
      results = jsonDecode(response["body"]);

      // For each package, change state of the package to Notified
      for (var element in results) {
        var responseNotified = await httpUtils.patch(
            "executeActions",
            Uri.parse(
                url + "/deployment/results/" + element["id"].toString() + "/"),
            httpUtils.getHeader(config),
            "{\"status\": 2, \"comment\": \"Notified\"}");
        logger.verbose(responseNotified["message"]);
      }
      return true;
    } else {
      logger.info("Any package has been found on the server.");
      return false;
    }
  }

  /// Get actions from assigned packages.
  Future<bool> getActions(int assetID) async {
    logger.info("Collecting actions...");

    // For each package, get the list of the package actions
    for (var element in results) {
      try {
        // API call: get the list of actions
        var response = await httpUtils.get(
            "getActions",
            Uri.parse(url +
                "/deployment/actions/?package=" +
                element["package"].toString()),
            httpUtils.getHeader(config));
        // VERBOSE: show result of the query in verbose mode
        logger.verbose(response["message"]);

        if (response["status_code"] == 200) {
          // Add actions list of each package to the general actions list
          actions.putIfAbsent(element["package"], () => response["body"]);

          logger.serverLogger(
              assetID,
              7,
              "Actions collected on package " +
                  element["package"].toString() +
                  ".");
        } else {
          logger.error("Can't collect actions from the server.");
          logger.serverLogger(
              assetID,
              8,
              "Can't collect actions from the server for the package " +
                  element["package"].toString() +
                  ".");
          return false;
        }
      } catch (exception) {
        logger.error(sprintf("HTTP query: %s", [exception.toString().trim()]));
        return false;
      }
    }
    logger.info("Actions collected");
    return true;
  }

  /// Execute actions from assigned packages.
  Future<void> executeActions(String os, int assetID) async {
    logger.info("Executing actions...");

    int id = 0;
    int status = 0;
    late bool success;

    // For each action, try to execute the command in the action object
    for (var element in actions.values) {
      success = false;

      // This for loop try the number of times of the parameter "max_retry" in the server config
      for (var _ in Iterable.generate(
          config.getCoreConfig("deployment", "max_retry"))) {
        // Exit the loop if the package has been installed successfully
        if (success == true) {
          break;
        }
        for (var action in jsonDecode(element)) {
          results.forEach((resultElement) {
            if (resultElement["package"] == action["package"]) {
              id = resultElement["id"];
            }
          });
          // VERBOSE: show which action is processing
          logger.verbose(action.toString());
          switch (action["action_type"]) {
            case "EXEC":
              status = await executeCommand(
                  os, action["package"], action["command"]);
              break;
            case "STORE":
              status = await storeFile(action["package"], action["file"]);
              break;
            case "LAUNCH":
              status = await launchFile(
                  os, action["package"], action["command"], action["file"]);
              break;
            default:
              logger.error("Canno't read correctly the action type!");
              logger.serverLogger(
                  assetID,
                  8,
                  "Can't get type from the action " +
                      action["name"].toString() +
                      ".");
              break;
          }
          // if process method don't send any error, the package has been installed successfully
          if (status == 0) {
            success = true;
          }
        }
      }
      if (status == 0) {
        try {
          // API call: send success to server if the package is installed
          var responseSuccess = await httpUtils.patch(
              "executeActions",
              Uri.parse(url + "/deployment/results/$id/"),
              httpUtils.getHeader(config),
              "{\"status\": 0, \"comment\": \"Success\"}");
          logger.verbose(responseSuccess["message"]);
          if (responseSuccess["status_code"] == 200) {
            logger.info("Package $id was completed successfully!");
            logger.serverLogger(
                assetID, 7, "Package $id was completed successfully!");
          }
        } catch (exception) {
          logger
              .error(sprintf("HTTP query: %s", [exception.toString().trim()]));
        }
      } else {
        try {
          // API call: send error to server if the package isn't installed
          var responseFail = await httpUtils.patch(
              "executeActions",
              Uri.parse(url + "/deployment/results/$id/"),
              httpUtils.getHeader(config),
              "{\"status\": 3, \"comment\": \"Error\"}");
          logger.verbose(responseFail["message"]);
          if (responseFail["status_code"] == 200) {
            logger.info("Package $id was not completed successfully!");
            logger.serverLogger(
                assetID, 8, "Package $id was not completed successfully!");
          }
        } catch (exception) {
          logger
              .error(sprintf("HTTP query: %s", [exception.toString().trim()]));
        }
      }
    }
  }

  /// Execute the action command.
  Future<int> executeCommand(
      String os, int package, String actionCommand) async {
    logger.info("Executing action command...");

    // This variables will replace variable by dynamic path
    Map<String, dynamic> variables = {
      "\$AGENT_PATH":
          Directory.current.toString().substring(11, null).replaceAll("'", "") +
              "/" +
              config.getInventoryConfig("data_dir"),
      "\$PACKAGE": "deployment/" + package.toString()
    };
    variables.keys.forEach((key) {
      actionCommand = actionCommand.replaceAll(key, variables[key]);
    });

    int status = 0;
    String result = "";

    // Depending of the plateform, execute a command with appropriate CLI
    switch (os) {
      case "LIN":
        var command = LinuxCommand();

        result = await command.commandShell(actionCommand, true).timeout(
            Duration(
                days: config.getCoreConfig(
              "deployment",
              "execution_timeout",
            )), onTimeout: () {
          status = 1;
          return "TIMEOUT: Command execution time exceeded!";
        });
        break;
      case "MAC":
        var command = MacOSCommand();

        result = await command.commandShell(actionCommand, true).timeout(
            Duration(
                days: config.getCoreConfig(
              "deployment",
              "execution_timeout",
            )), onTimeout: () {
          status = 1;
          return "TIMEOUT: Command execution time exceeded!";
        });
        break;
      case "WIN":
        var command = WindowsCommand();

        result = await command.commandPowershell(actionCommand, true).timeout(
            Duration(
                days: config.getCoreConfig(
              "deployment",
              "execution_timeout",
            )), onTimeout: () {
          status = 1;
          return "TIMEOUT: Command execution time exceeded!";
        });
        break;
      default:
        logger.error(
            "OS does not match any of the supported OSs! (Check Plateform class return)");
        break;
    }
    if (status == 0) {
      logger.verbose(result);
      logger.info("Action command executed successfully!");
    } else {
      logger.error(result);
    }
    return status;
  }

  /// Only store the file without execution
  Future<int> storeFile(int package, String filePath) async {
    logger.info("Downloading and storing file...");

    // Get the package directory or create one if not exist
    var packageDirectory = Directory(config.getInventoryConfig("data_dir") +
        "/deployment/" +
        package.toString());
    if (!packageDirectory.existsSync()) {
      packageDirectory.createSync(recursive: true);
    }

    int status = 0;
    var client = HttpClient();
    // Try to download and store the file in the package folder
    try {
      HttpClientRequest request = await client.getUrl(Uri.parse(filePath));
      HttpClientResponse response = await request.close();
      await response
          .pipe(File(config.getInventoryConfig("data_dir") +
                  "/deployment/" +
                  package.toString() +
                  "/" +
                  filePath.split("/").last)
              .openWrite())
          .timeout(
              Duration(
                  days: config.getCoreConfig(
                "deployment",
                "download_timeout",
              )), onTimeout: () {
        status = 1;
        logger.error("TIMEOUT: Download time exceeded!");
      });
    } finally {
      client.close();
    }

    if (status == 0) {
      logger.info("File downloaded and stored!");
    } else {
      logger.error("Failed to download and store the file!");
    }
    return status;
  }

  /// Store the specified file and execute it.
  Future<int> launchFile(
      String os, int package, String actionCommand, String filePath) async {
    int storeStatus = await storeFile(package, filePath);
    int execStatus = await executeCommand(os, package, actionCommand);
    int status = 0;
    if (storeStatus != 0 || execStatus != 0) {
      status = 1;
    }
    return status;
  }
}
