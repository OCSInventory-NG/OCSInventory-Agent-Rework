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
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocsinventory_agent/core/log.dart';
import 'package:ocsinventory_agent/core/config.dart';
import 'package:ocsinventory_agent/core/inventory/commands.dart';

// Common imports
import 'package:ocsinventory_agent/core/common/http_utils.dart';

class Deployment {
  late Config config;
  late Logger logger;
  late HTTPUtils httpUtils;
  late Commands commands;

  late var url;

  late List<dynamic> results;
  late Map<int, dynamic> actions;
  late List<dynamic> sortedActions;

  /// Constructor.
  Deployment(this.logger, this.config, this.httpUtils, this.commands) {
    url = config.getInventoryConfig("url");
    actions = Map();
    sortedActions = [];
  }

  /// Check the configuration of the deployment module.
  Future<bool> checkConfig() async {
    logger.info(this.runtimeType.toString(),
        "Checking deployment module configuration...");

    // Check if the URL is set
    if (url == null) {
      logger.error(this.runtimeType.toString(),
          "URL is missing in the configuration file.");
      return false;
    }

    // Check if the URL is valid
    if (!Uri.parse(url).isAbsolute) {
      logger.error(this.runtimeType.toString(),
          "URL in the configuration file is not valid.");
      return false;
    }

    // Check if the URL is reachable
    var response = await httpUtils.get(
        Uri.parse(url + "/deployment/results/"), httpUtils.getHeader());
    if (response["status_code"] == 200) {
      logger.info(
          this.runtimeType.toString(), "Deployment endpoint is reachable.");
      return true;
    } else {
      logger.error(
          this.runtimeType.toString(), "Deployment endpoint is not reachable.");
      return false;
    }
  }

  /// Make an API call to the deployment endpoint and handle the response
  Future<Map<String, dynamic>> _makeDeploymentApiCall(
      String endpoint, Map<String, String> params) async {
    var uri = Uri.parse(url + endpoint).replace(queryParameters: params);
    var response = await httpUtils.get(uri, httpUtils.getHeader());
    logger.debug(this.runtimeType.toString(), response["message"]);

    return {
      "status_code": response["status_code"],
      "body": response["body"],
      "success": response["status_code"] == 200
    };
  }

  /// Check if there is packages to download.
  Future<bool> checkDownload(int assetID) async {
    // API call: Check if there is assigned packages
    try {
      var response = await _makeDeploymentApiCall(
          "/deployment/results/", {"asset": assetID.toString(), "status": "1"});

      if (response["status_code"] == 200 &&
          jsonDecode(response["body"]).isNotEmpty) {
        logger.info(this.runtimeType.toString(), "Found assigned packages.");

        // Get the list of assigned packages
        results = jsonDecode(response["body"]);

        // For each package, change state of the package to Notified
        for (var element in results) {
          try {
            var responseNotified = await httpUtils.patch(
                Uri.parse(url +
                    "/deployment/results/" +
                    element["id"].toString() +
                    "/"),
                httpUtils.getHeader(),
                "{\"status\": 2, \"comment\": \"Notified\"}");
            logger.debug(
                this.runtimeType.toString(), responseNotified["message"]);
          } catch (exception) {
            logger.error(
                this.runtimeType.toString(),
                sprintf("Failed to update package status: %s",
                    [exception.toString().trim()]));
            return false;
          }
        }
        return true;
      } else {
        logger.info(this.runtimeType.toString(),
            "No assigned packages found for this asset.");
        return false;
      }
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      return false;
    }
  }

  /// Get actions from assigned packages.
  Future<bool> getActions(int assetID) async {
    logger.info(this.runtimeType.toString(), "Collecting actions...");

    // For each package, get the list of the package actions
    for (var element in results) {
      try {
        // API call: get the list of actions
        var response = await _makeDeploymentApiCall(
            "/deployment/actions/", {"package": element["package"].toString()});

        if (response["status_code"] == 200) {
          // Sort the actions by priority
          sortedActions = jsonDecode(response["body"]);
          sortedActions.sort((a, b) => a["priority"].compareTo(b["priority"]));
          // Add sorted actions list of each package to the general actions list
          actions.putIfAbsent(element["package"], () => sortedActions);

          logger.serverLogger(
              assetID,
              7,
              "Collected actions from the server for the package " +
                  element["package"].toString() +
                  ".");
        } else {
          logger.error(
              this.runtimeType.toString(),
              "Failed to collect actions from the server for the package " +
                  element["package"].toString() +
                  ".");
          logger.serverLogger(
              assetID,
              8,
              "Failed to collect actions from the server for the package " +
                  element["package"].toString() +
                  ".");
          return false;
        }
      } catch (exception) {
        logger.error(this.runtimeType.toString(),
            sprintf("HTTP query: %s", [exception.toString().trim()]));
        return false;
      }
    }
    logger.info(this.runtimeType.toString(), "Actions collected successfully.");
    return true;
  }

  /// Handle the result of an action execution
  /// Returns a map containing the action status and any error message
  Map<String, dynamic> handleActionResult({
    required String actionType,
    required Map<String, dynamic> result,
    required String successMessage,
    required int actionId,
    required Map<String, String> actionErrors,
  }) {
    int actionStatus = result["status"] == true ? 0 : 1;
    String errorComment = "Error";

    if (actionStatus == 0) {
      logger.info(this.runtimeType.toString(), successMessage);
    } else {
      result["error"].toString().trim().isEmpty ? result["error"] = "Unknown error: No output" : result["error"];
      errorComment = "Error $actionType: ${result["error"]}";
      logger.error(this.runtimeType.toString(), errorComment);
      actionErrors["$actionId"] = result["error"];
    }

    return {
      "actionStatus": actionStatus,
      "errorComment": errorComment,
      "status": actionStatus == 0 ? 0 : 1
    };
  }

  /// Execute actions from assigned packages.
  Future<void> executeActions(String os, int assetID) async {
    logger.info(this.runtimeType.toString(), "Executing actions...");

    int id = 0;
    int status = 0;
    int packageCount = 0;
    String errorComment = "Error";
    Map<String, String> actionErrors = {};

    if (os != "WIN" && os != "MAC" && os != "LIN") {
      logger.error(this.runtimeType.toString(), "Unsupported OS detected.");
      return;
    }

    if (assetID < 0) {
      logger.error(this.runtimeType.toString(), "Invalid asset ID detected.");
      return;
    }

    for (var element in actions.values) {
      // delay between pkgs
      if (packageCount > 0) {
        int latencySeconds =
            config.getCoreConfig("deployment", "period_latency");
        logger.info(this.runtimeType.toString(),
            "Waiting $latencySeconds seconds before processing next package...");
        await Future.delayed(Duration(seconds: latencySeconds));
      }
      packageCount++;

      // clear actions errors
      actionErrors.clear();
      status = 0;

      for (var action in element) {
        logger.debug(this.runtimeType.toString(),
            "Processing action: ${action.toString()}");

        results.forEach((resultElement) {
          if (resultElement["package"] == action["package"]) {
            id = resultElement["id"];
          }
        });
        String packagePath = config.getInventoryConfig("data_directory") +
            "/deployment/" +
            action["package"].toString() +
            "/";
        // VERBOSE: show which action is processing
        logger.debug(this.runtimeType.toString(), action.toString());

        //clear comment
        errorComment = "Error";
        int actionStatus = 0;

        switch (action["action_type"]) {
          case "EXEC":
            Map<String, dynamic> execResult =
                await executeCommand(os, action["package"], action["command"]);
            var result = handleActionResult(
              actionType: "executing command",
              result: execResult,
              successMessage: "Command executed successfully.",
              actionId: action["id"],
              actionErrors: actionErrors,
            );
            actionStatus = result["actionStatus"];
            errorComment = result["errorComment"];
            status = result["status"];
            break;
          case "STORE":
            String fileUrl = action["file"]["file"];
            Map<String, dynamic> storeResult = await storeFile(
                action["package"],
                fileUrl,
                action["command"],
                action["action_type"],
                os);
            var result = handleActionResult(
              actionType: "storing file",
              result: storeResult,
              successMessage:
                  "File has been successfully downloaded and saved.",
              actionId: action["id"],
              actionErrors: actionErrors,
            );
            actionStatus = result["actionStatus"];
            errorComment = result["errorComment"];
            status = result["status"];

            if (actionStatus == 0) {
              // Delete the package directory after storing the file
              var packageDirectory = Directory(packagePath);
              if (packageDirectory.existsSync()) {
                try {
                  await packageDirectory.delete(recursive: true);
                  logger.debug(this.runtimeType.toString(),
                      "Deleted package directory at: '$packagePath'");
                } catch (exception) {
                  logger.error(
                      this.runtimeType.toString(),
                      sprintf("Failed to delete package directory: %s",
                          [exception.toString().trim()]));
                }
              }
            }
            break;
          case "LAUNCH":
            String fileUrl = action["file"]["file"];
            Map<String, dynamic> launchResult = await launchFile(
                os,
                action["package"],
                action["command"],
                fileUrl,
                action["action_type"]);
            var result = handleActionResult(
              actionType: "launching file",
              result: launchResult,
              successMessage: "File launched successfully.",
              actionId: action["id"],
              actionErrors: actionErrors,
            );
            actionStatus = result["actionStatus"];
            errorComment = result["errorComment"];
            status = result["status"];

            // Delete the package directory after launching the file
            var packageDirectory = Directory(packagePath);
            if (packageDirectory.existsSync()) {
              try {
                await packageDirectory.delete(recursive: true);
                logger.debug(this.runtimeType.toString(),
                    "Deleted package directory at: '$packagePath'");
              } catch (exception) {
                logger.error(
                    this.runtimeType.toString(),
                    sprintf("Failed to delete package directory: %s",
                        [exception.toString().trim()]));
              }
            }
            break;
          default:
            errorComment =
                "Unknown action type: " + action["action_type"].toString();
            logger.error(this.runtimeType.toString(), errorComment);
            logger.serverLogger(assetID, 8, errorComment);
            // store error
            actionErrors["${action["id"]}"] =
                "Unknown action type: ${action["action_type"]}";
            status = 1;
            break;
        }
      }

      if (status == 0) {
        try {
          // API call: send success to server if the package is installed
          var responseSuccess = await httpUtils.patch(
              Uri.parse(url + "/deployment/results/$id/"),
              httpUtils.getHeader(),
              "{\"status\": 0, \"comment\": \"Success\"}");
          logger.debug(this.runtimeType.toString(), responseSuccess["message"]);
          if (responseSuccess["status_code"] == 200) {
            logger.info(this.runtimeType.toString(),
                "Package $id has been successfully processed.");
            logger.serverLogger(
                assetID, 7, "Package $id has been successfully processed.");
          }
        } catch (exception) {
          logger.error(this.runtimeType.toString(),
              sprintf("HTTP query: %s", [exception.toString().trim()]));
        }
      } else {
        try {
          // Format the error comment based on number of actions with errors
          String formattedErrorComment;
          if (actionErrors.length == 1) {
            // If only one action has an error, use the simple format with just the error message
            String actionId = actionErrors.keys.first;
            formattedErrorComment = actionErrors[actionId]!;
          } else {
            // If multiple actions have errors, use JSON format with action IDs as keys
            formattedErrorComment = jsonEncode(actionErrors);
          }

          // API call: send error to server if the package isn't installed
          var responseFail = await httpUtils.patch(
              Uri.parse(url + "/deployment/results/$id/"),
              httpUtils.getHeader(),
              "{\"status\": 3, \"comment\": ${jsonEncode(formattedErrorComment)}}");
          logger.debug(this.runtimeType.toString(), responseFail["message"]);
          if (responseFail["status_code"] == 200) {
            logger.error(this.runtimeType.toString(),
                "Something went wrong while processing package $id: $formattedErrorComment");
            logger.serverLogger(assetID, 8,
                "Something went wrong while processing package $id: $formattedErrorComment");
          }
        } catch (exception) {
          logger.error(this.runtimeType.toString(),
              sprintf("HTTP query: %s", [exception.toString().trim()]));
        }
      }
    }
  }

  /// Execute the action command.
  Future<Map<String, dynamic>> executeCommand(
      String os, int package, String actionCommand) async {
    logger.info(this.runtimeType.toString(), "Executing action command...");

    // This variables will replace variable by dynamic path
    Map<String, dynamic> variables = {
      "\$AGENT_PATH":
          Directory.current.toString().substring(11, null).replaceAll("'", "") +
              "/" +
              config.getInventoryConfig("data_directory"),
      "\$PACKAGE": "deployment/" + package.toString()
    };
    variables.keys.forEach((key) {
      actionCommand = actionCommand.replaceAll(key, variables[key]);
    });

    Map<String, dynamic> result = {"value": "", "status": false, "error": ""};
    int retryCounter = 0;

    do {
      result = {"value": "", "status": false, "error": ""};

      // Depending of the plateform, execute a command with appropriate CLI
      String method = "";

      switch (os) {
        case "LIN":
        case "MAC":
          method = "BASH";

        case "WIN":
          method = "PW";

        default:
          logger.error(this.runtimeType.toString(), "Unsupported OS detected.");
          result["error"] = "Unsupported OS detected.";
          break;
      }

      result = await commands
          .processTarget(method, actionCommand, "Deployment", "")
          .then((value) {
        return value;
      }).catchError((onError) {
        logger.error(this.runtimeType.toString(),
            "Error while executing action command: $onError");
        return {"value": "", "status": false, "error": onError.toString()};
      }).timeout(
              Duration(
                  days: config.getCoreConfig(
                "deployment",
                "execution_timeout",
              )), onTimeout: () {
        logger.error(this.runtimeType.toString(),
            "Error while executing action command: TIMEOUT");
        return {"value": "", "status": false, "error": "TIMEOUT"};
      });

      if (config.getCoreConfig("deployment", "max_retry") >= retryCounter &&
          config.getCoreConfig("deployment", "auto_retry") &&
          result["status"] == false &&
          retryCounter > 0) {
        logger.error(this.runtimeType.toString(),
            "Command execution failed on retry #${retryCounter}: ${result["error"]}");
      }
      retryCounter++;
    } while (result["status"] == false &&
        config.getCoreConfig("deployment", "max_retry") >= retryCounter &&
        config.getCoreConfig("deployment", "auto_retry"));

    if (result["status"] == true) {
      logger.debug(this.runtimeType.toString(), result["value"].toString());
    }

    return result;
  }

  /// Extracts a zip file to the specified path and performs cleanup.
  ///
  /// This function decompresses the provided zip archive data and extracts its
  /// contents to the specified path. After extraction, it deletes the metadata
  /// directory if it exists.
  ///
  /// Parameters:
  ///   - extractedPath: The path where the contents of the zip archive will be extracted.
  ///   - savedFile: The file object representing the zip archive file.
  ///   - metaDataPath: The path to the metadata directory to be deleted.
  ///   - status: The status indicator. If an error occurs during extraction,
  ///             status will be set to 1.
  ///
  /// Returns:
  ///   A Future<void> representing the completion of the extraction process.
  ///
  /// Throws:
  ///   Any error that occurs during the extraction process.
  Future<Map<String, dynamic>> extractZipFile(String extractedPath,
      File savedFile, String metaDataPath, bool status) async {
    Map<String, dynamic> result = {"status": false, "error": ""};

    try {
      // read saved file
      List<int> fileBytes = await savedFile.readAsBytes();
      // Decompress the zip archive
      var archive = ZipDecoder().decodeBytes(fileBytes);
      await extractArchiveToDisk(archive, extractedPath);
      // Log verbose message indicating successful extraction
      logger.debug(this.runtimeType.toString(),
        "File has been extracted at: '$extractedPath'");

      // Delete the __MACOSX directory if it exists
      var metaDataDirectory = Directory(metaDataPath);
      if (metaDataDirectory.existsSync()) {
        metaDataDirectory.delete(recursive: true);
      }
      // Delete the archive file after extracting it
      if (savedFile.existsSync()) {
        savedFile.deleteSync();
      }
      result["status"] = true;
    } catch (e) {
      result["status"] = false;
      result["error"] = "Exception during zip extraction: $e";
      logger.error(this.runtimeType.toString(), result["error"]);
    }

    return result;
  }

  /// Extracts a tar file to the specified path and deletes the archive file.
  ///
  /// This function extracts the contents of a tar archive file to the specified
  /// path using the `tar` command. After extraction, it deletes the archive file.
  ///
  /// Parameters:
  ///   - filePath: The path to the tar archive file to be extracted.
  ///   - extractedPath: The path where the contents of the tar archive will be extracted.
  ///   - savedFile: The file object representing the tar archive file.
  ///   - status: The status indicator. If an error occurs during extraction,
  ///             status will be set to 1.
  ///
  /// Returns:
  ///   A Future<void> representing the completion of the extraction process.
  ///
  /// Throws:
  ///   Any error that occurs during the extraction process.
  Future<Map<String, dynamic>> extractTarFile(String filePath,
      String extractedPath, File savedFile, bool status, String os) async {
    Map<String, dynamic> result = {"status": false, "error": ""};

    if (os != "LIN" && os != "MAC") {
      result["error"] = "Unsupported OS detected while extracting tar file.";
      logger.error(this.runtimeType.toString(), result["error"]);
      return result;
    }

    logger.debug(this.runtimeType.toString(),
        "Extracting tar file: '$filePath' to path: '$extractedPath'");

    try {
      // Execute the tar command to extract the archive file
      var cmdResult = await commands.processTarget(
          "BASH", "tar -xvf $filePath -C $extractedPath", "Deployment", "");

      if (cmdResult["status"] == true) {
        // Delete the archive file after extracting it
        if (savedFile.existsSync()) {
          // Log verbose message indicating successful extraction
          logger.debug(this.runtimeType.toString(),
              "File has been extracted at: '$extractedPath'");

          savedFile.deleteSync();
          result["status"] = true;
        } else {
          result["error"] = "Archive file no longer exists after extraction";
          result["status"] = false;
        }
      } else {
        // Handle extraction error
        result["error"] =
            "Error extracting file: ${cmdResult["error"] ?? cmdResult["value"]}";
        logger.error(this.runtimeType.toString(), result["error"]);
        result["status"] = false;
      }
    } catch (e) {
      result["error"] = "Exception during tar extraction: $e";
      logger.error(this.runtimeType.toString(), result["error"]);
      result["status"] = false;
    }
    return result;
  }

  /// Downloads a file from a given URL and stores it locally.
  ///
  /// This function downloads a file from a specified URL and stores it locally
  /// in the agent's directory. Optionally, it can also store the file in a
  /// specified directory if the action type is "STORE". It supports
  /// downloading and storing both regular files and compressed files (tar and zip).
  ///
  /// Parameters:
  ///   - package: The package identifier.
  ///   - filePath: The URL of the file to download.
  ///   - pathToStore: The path where the file will be stored locally.
  ///   - actionType: The action type, either "STORE" or another value.
  ///   - os: The operating system of the agent.
  ///
  /// Returns:
  ///   An integer status code indicating the success or failure of the operation.
  ///   - 0: Success
  ///   - 1: Failure
  Future<Map<String, dynamic>> storeFile(int package, String filePath,
      String pathToStore, String actionType, String os) async {
    logger.info(this.runtimeType.toString(), "Downloading and saving file...");
    logger.debug(this.runtimeType.toString(), "File path structure: $filePath");

    // extract actual URL if filePath is a Map
    String fileUrl;
    if (filePath is Map<String, dynamic>) {
      fileUrl = (filePath as Map<String, dynamic>)["file"] as String;
      logger.debug(this.runtimeType.toString(), "Extracted file URL: $fileUrl");
    } else {
      fileUrl = filePath;
    }

    // Get the package directory or create one if not exist
    var packageDirectory = Directory(
        config.getInventoryConfig("data_directory") +
            "/deployment/" +
            package.toString());
    if (!packageDirectory.existsSync()) {
      packageDirectory.createSync(recursive: true);
    }

    Map<String, dynamic> result = {"status": false, "error": ""};
    int retryCounter = 0;

    Future<String> completerValue = Future.value("");
    // Store the file in the agent directory - use the last part of the URL for filename
    String localPath = config.getInventoryConfig("data_directory") +
        "/deployment/" +
        package.toString() +
        "/";
    var fileSaveLocal = new File(localPath + fileUrl.split("/").last);

    String specifiedPath =
        pathToStore.endsWith("/") ? pathToStore : pathToStore + "/";

    // Check if the specified path exists
    if (actionType == "STORE") {
      var specifiedDirectory = Directory(specifiedPath);
      if (!specifiedDirectory.existsSync()) {
        result["error"] = "Specified path does not exist: $specifiedPath";
        logger.error(this.runtimeType.toString(), result["error"]);
        return result;
      }
    }

    do {
      // Try to download and store the file in the package folder
      bool responseStreamStatus = false;
      Completer<String> completer = Completer<String>();
      try {
        result["status"] = false;
        result["error"] = "";

        httpUtils.getStream(Uri.parse(fileUrl), {}).then((response) {
          if (response.statusCode == HttpStatus.ok) {
            logger.debug(this.runtimeType.toString(),
                "Successfully downloaded file: $fileUrl");
            response.stream.pipe(fileSaveLocal.openWrite()).then((fileAdded) async {
              // Save the file directly if not zipped

              if (fileAdded.existsSync()) {
                responseStreamStatus = true;
                if (fileUrl.endsWith('.tar') ||
                    fileUrl.endsWith('.tar.gz') ||
                    fileUrl.endsWith('.zip') ||
                    fileUrl.endsWith('.tar.xz') ||
                    fileUrl.endsWith('.tgz') ||
                    fileUrl.endsWith('.tar.bz2')) {
                  switch (os) {
                    case "LIN":
                      if ((fileUrl.endsWith('.tar') ||
                              fileUrl.endsWith('.tar.gz') ||
                              fileUrl.endsWith('.tar.xz') ||
                              fileUrl.endsWith('.tgz') ||
                              fileUrl.endsWith('.tar.bz2')) &&
                          responseStreamStatus == true) {
                        // Decompress the tar archive
                        Map<String, dynamic> extractResult =
                            await extractTarFile(
                                localPath + fileUrl.split("/").last,
                                specifiedPath,
                                fileSaveLocal,
                                responseStreamStatus,
                                os);
                        responseStreamStatus = extractResult["status"];
                        if (!responseStreamStatus) {
                          result["error"] = extractResult["error"];
                        }
                      }
                      if (fileUrl.endsWith('.zip')) {
                        result["error"] =
                            "Zip format is not supported for Linux: $fileUrl";
                        logger.error(
                            this.runtimeType.toString(), result["error"]);
                        responseStreamStatus = false;
                      }
                      break;

                    case "MAC":
                      if ((fileUrl.endsWith('.tar') ||
                              fileUrl.endsWith('.tar.gz') ||
                              fileUrl.endsWith('.tar.xz') ||
                              fileUrl.endsWith('.tgz') ||
                              fileUrl.endsWith('.tar.bz2')) &&
                          responseStreamStatus == true) {
                        // Decompress the tar archive
                        Map<String, dynamic> extractResult =
                            await extractTarFile(
                                localPath + fileUrl.split("/").last,
                                specifiedPath,
                                fileSaveLocal,
                                responseStreamStatus,
                                os);
                        responseStreamStatus = extractResult["status"];
                        if (!responseStreamStatus) {
                          result["error"] = extractResult["error"];
                        }
                      }
                      if (fileUrl.endsWith('.zip') &&
                          responseStreamStatus == true) {
                        // Determine the local path to the meta data directory
                        String metaDataPath = localPath + "/__MACOSX";

                        // Decompress the zip archive
                        Map<String, dynamic> extractResult =
                            await extractZipFile(specifiedPath, fileSaveLocal,
                                metaDataPath, responseStreamStatus);
                        responseStreamStatus = extractResult["status"];
                        if (!responseStreamStatus) {
                          result["error"] = extractResult["error"];
                        }
                      }
                      break;

                    case "WIN":
                      if ((fileUrl.endsWith('.zip')) &&
                          responseStreamStatus == true) {
                        // Determine the local path to the meta data directory
                        String metaDataPath = localPath + "/__MACOSX";

                        // Decompress the zip archive
                        Map<String, dynamic> extractResult =
                            await extractZipFile(specifiedPath, fileSaveLocal,
                                metaDataPath, responseStreamStatus);
                        responseStreamStatus = extractResult["status"];
                        if (!responseStreamStatus) {
                          result["error"] = extractResult["error"];
                        }
                      }
                      if (fileUrl.endsWith('.tar') ||
                          fileUrl.endsWith('.tar.gz')) {
                        result["error"] =
                            "Tar format is not supported for Windows: $fileUrl";
                        logger.error(
                            this.runtimeType.toString(), result["error"]);
                        responseStreamStatus = false;
                      }
                      break;

                    default:
                      result["error"] =
                          "Unsupported OS detected while storing file: $fileUrl";
                      logger.error(
                          this.runtimeType.toString(), result["error"]);
                      responseStreamStatus = false;
                  }
                } else {
                  logger.debug(this.runtimeType.toString(),
                      "The file $fileUrl has been saved in the agent directory at: '$localPath'");
                  if (actionType == "LAUNCH") {
                    // Make the file executable
                    String chmodCommand = "chmod +x ${fileAdded.path}";
                    Map<String, dynamic> chmodResult =
                        await executeCommand(os, package, chmodCommand);
                    if (!chmodResult["status"]) {
                      result["error"] =
                          "Failed to make file executable: ${chmodResult["error"]}";
                      responseStreamStatus = false;
                    }
                  }

                  if (actionType == "STORE") {
                    try {
                      File remoteFile = await fileAdded
                          .copySync(specifiedPath + fileUrl.split("/").last);
                      if (remoteFile.existsSync() &&
                          remoteFile.lengthSync() == fileAdded.lengthSync()) {
                        logger.debug(this.runtimeType.toString(),
                            "The file $fileUrl has been successfully saved at the specified path: '$specifiedPath'");
                        responseStreamStatus = true;
                      } else {
                        result["error"] =
                            "Error encountered while saving the file to the specified path: $specifiedPath";
                        logger.error(
                            this.runtimeType.toString(), result["error"]);
                        responseStreamStatus = false;
                      }
                    } catch (e) {
                      result["error"] = "Error copying file to destination: $e";
                      logger.error(
                          this.runtimeType.toString(), result["error"]);
                      responseStreamStatus = false;
                    }
                  }
                }
              } else {
                result["error"] =
                    "An error occurred while attempting to save the file to the agent directory";
                logger.error(this.runtimeType.toString(), result["error"]);
                responseStreamStatus = false;
              }

              // Complete the completer with the final value of responseStreamStatus
              completer.complete(responseStreamStatus.toString());
            }, onError: (error) {
              responseStreamStatus = false;
              result["error"] = "Error while downloading file: $error";
              logger.error(this.runtimeType.toString(), result["error"]);
              // Complete the completer with error
              completer.completeError(error);
            }).timeout(
                Duration(
                    seconds: config.getCoreConfig(
                        "deployment", "deployment_timeout")), onTimeout: () {
              responseStreamStatus = false;
              result["error"] = "Error while downloading file: TIMEOUT";
              logger.error(this.runtimeType.toString(), result["error"]);
              // Complete the completer with error
              completer.completeError("TIMEOUT");
            });
          } else {
            completer.complete(responseStreamStatus.toString());
            result["error"] =
                "Failed to download file: ${response.reasonPhrase} ${fileUrl}";
            if (config.getCoreConfig("deployment", "max_retry") >=
                    retryCounter &&
                config.getCoreConfig("deployment", "auto_retry") &&
                responseStreamStatus == false &&
                retryCounter > 0) {
              logger.error(this.runtimeType.toString(),
                  "File save failed on retry #${retryCounter}: ${result["error"]}");
              responseStreamStatus = false;
              return response.stream.drain();
            } else {
              logger.error(this.runtimeType.toString(), result["error"]);
              responseStreamStatus = false;
              return response.stream.drain();
            }
          }
        });
      } finally {
        // Get the future from the completer
        completerValue = completer.future;
      }

      await completerValue.then((value) async {
        if (value == "true") {
          result["status"] = true;
        } else {
          result["status"] = false;
        }
      }).catchError((error) {
        result["error"] = "Failed to download and save file: $error";
        logger.error(this.runtimeType.toString(), result["error"]);
        result["status"] = false;
      });

      retryCounter++;
    } while (result["status"] == false &&
        config.getCoreConfig("deployment", "max_retry") >= retryCounter &&
        config.getCoreConfig("deployment", "auto_retry"));

    return result;
  }

  /// Store the specified file and execute it.
  Future<Map<String, dynamic>> launchFile(String os, int package,
      String actionCommand, dynamic filePath, String actionType) async {
    logger.info(this.runtimeType.toString(), "Launching file...");
    logger.debug(this.runtimeType.toString(),
        "Launch file parameters - Command: $actionCommand, File: $filePath");

    // use package dir as extract path
    String packagePath = config.getInventoryConfig("data_directory") +
        "/deployment/" +
        package.toString() +
        "/";

    logger.debug(this.runtimeType.toString(),
        "Using package directory for extraction: '$packagePath'");

    Map<String, dynamic> result = {"status": 1, "error": ""};

    Map<String, dynamic> storeResult =
        await storeFile(package, filePath, packagePath, actionType, os);
    bool storeStatus = storeResult["status"];

    logger.debug(this.runtimeType.toString(),
        "File store operation result: ${storeStatus ? 'Success' : 'Failed'}");

    if (!storeStatus) {
      result["error"] = "Failed to store file: ${storeResult["error"]}";
      return result;
    }

    //  listing files to ensure extraction went well
    List<String> extractedFiles = [];
    try {
      var files = Directory(packagePath).listSync();
      extractedFiles = files.map((f) => f.path.split('/').last).toList();
      logger.debug(this.runtimeType.toString(),
          "Files in package directory: ${extractedFiles.join(', ')}");
    } catch (e) {
      logger.error(this.runtimeType.toString(),
          "Error listing files in package directory: $e");
    }

    // keeping the current dir
    String originalDir = Directory.current.path;

    // then switching to the pkg dir for contextual exec
    Directory.current = Directory(packagePath);
    logger.debug(this.runtimeType.toString(),
        "Changed working directory to: '${Directory.current.path}'");

    Map<String, dynamic> execResult =
        await executeCommand(os, package, actionCommand);
    bool execStatus = execResult["status"];

    // back to the original dir
    Directory.current = Directory(originalDir);
    logger.debug(this.runtimeType.toString(),
        "Restored working directory to: '${Directory.current.path}'");

    logger.debug(this.runtimeType.toString(),
        "Command execution result: ${execStatus ? 'Success' : 'Failed'}");

    if (!execStatus) {
      result["error"] = "Failed to execute command: ${execResult["error"]}";
      return result;
    }

    result["status"] = storeStatus && execStatus;
    return result;
  }

  /// check if deployment is enabled then process packages and actions
  Future<void> processDeployment(String os, int assetID) async {
    if (config.getCoreConfig("deployment", "enabled")) {
      logger.info(this.runtimeType.toString(),
          "Deployment is enabled in server configuration.");
      if (await checkConfig()) {
        if (await checkDownload(assetID)) {
          if (await getActions(assetID)) {
            await executeActions(os, assetID);
          }
        }
      }
    } else {
      logger.info(this.runtimeType.toString(),
          "Deployment is disabled in server configuration.");
    }
  }
}
