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
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocs_agent/core/log.dart';
import 'package:ocs_agent/core/config.dart';

import 'package:ocs_agent/core/inventory/linux/commands.dart';
import 'package:ocs_agent/core/inventory/linux/format.dart';

import 'package:ocs_agent/core/inventory/macos/commands.dart';
import 'package:ocs_agent/core/inventory/macos/format.dart';

import 'package:ocs_agent/core/inventory/windows/commands.dart';
import 'package:ocs_agent/core/inventory/windows/format.dart';

// Common imports
import 'package:ocs_agent/core/common/files_utils.dart';
import 'package:ocs_agent/core/common/http_utils.dart';
import 'package:ocs_agent/core/common/json_utils.dart';

class Inventory {
  late Logger logger;
  late Config config;
  late FilesUtils filesUtils;
  late HTTPUtils httpUtils;
  late JsonUtils jsonUtils;
  late LinuxCommand linuxCommand;
  late LinuxFormat linuxFormat;
  late MacOSCommand macOSCommand;
  late MacOSFormat macOSFormat;
  late WindowsCommand windowsCommand;
  late WindowsFormat windowsFormat;

  late var baseUrl;
  late bool inventoryCheck;
  late int assetID;

  late String inventoryFileName;
  late File inventoryFile;
  late File inventoryBase64;

  late Map<int, String> errorCodes;

  final JsonEncoder encoder = JsonEncoder.withIndent("\t");

  /// Constructor.
  Inventory(
    this.logger,
    this.config,
    this.filesUtils,
    this.httpUtils,
    this.jsonUtils,
    this.linuxCommand,
    this.linuxFormat,
    this.macOSCommand,
    this.macOSFormat,
    this.windowsCommand,
    this.windowsFormat,
  ) {
    List<String> configFields = ["url", "data_directory"];
    String? dataDirectory;

    try {
      List<String> inventoryData = getInventoryData(configFields);

      if (inventoryData.length == 2) {
        this.baseUrl = inventoryData[0];
        dataDirectory = inventoryData[1];
      }
    } catch (e) {
      logError("Configuration missing fields: $e");
      this.baseUrl = "";
    }

    this.inventoryCheck = false;
    this.assetID = 0;

    this.inventoryFileName = sprintf('%s/%s.json', [
      dataDirectory,
      DateFormat("yyyy-MM-dd_HH-mm-ss").format(DateTime.now())
    ]);
    this.inventoryFile = File(inventoryFileName);
    this.inventoryBase64 =
        File(sprintf('%s/%s.json', [dataDirectory, "Base64"]));

    this.errorCodes = {};
  }

  /// Get the running mode of the agent.
  int getMode() {
    return config.getInventoryConfig("mode");
  }

  /// Check if API is working and generate a token if it doesn't exist.
  Future<bool> checkApi() async {
    List<String> requiredFields = ["username", "password"];
    String username = "", password = "", localToken = "";

    // Check OCS API status
    logInfo("Checking API availability...");

    dynamic responseGet = await sendApiRequest("GET", baseUrl);

    try {
      List<String> inventoryData = getInventoryData(requiredFields);
      if (inventoryData.length == 2) {
        username = inventoryData[0];
        password = inventoryData[1];
      } else {
        throw ("Invalid number of config fields.");
      }

      // Optional retrieval of the token (can be empty on first run)
      localToken = config.getInventoryConfig("token") ?? "";

      await generateToken(username, password, localToken);
    } catch (e) {
      logError("Configuration error: $e");
    }

    if (responseGet != null && responseGet["status_code"] == 200) {
      logVerbose(responseGet["message"]);
      logInfo("API is online!");

      return true;
    } else {
      logVerbose("Check username or password in the configuration file.");
      logError("API connection failed!");

      return false;
    }
  }

  /// Get one or more inventory config values as a String.
  List<String> getInventoryData(List<String> keys) {
    try {
      return keys.map((key) {
        String dataResult = config.getInventoryConfig(key) ?? "";

        if (dataResult.isEmpty) {
          throw ("Configuration missing field for key: $key");
        }

        return dataResult;
      }).toList();
    } catch (e) {
      logError("Error getting inventory config: $e");
      return [];
    }
  }

  /// Send to API the username and password and
  /// save the token retreived in inventory.json.
  Future<bool> generateToken(
      String username, String password, String localToken) async {
    logInfo("Generating token...");
    // Try to get the token generated by the server to save it in the inventory.json file

    // API call
    String url = baseUrl + "/api-auth/token";
    var header = {HttpHeaders.contentTypeHeader: 'application/json'};
    String jsonEncoded =
        jsonEncode({'username': username, 'password': password});
    dynamic responsePost =
        await sendApiRequest("POST", url, headers: header, body: jsonEncoded);

    if (responsePost != null && responsePost["status_code"] == 200) {
      logVerbose(responsePost["message"]);
      logInfo("Token retrieved successfully.");

      // Get the token from the response body and compare with the local token
      // If tokens are not the same, replace the local token with the server one
      var newToken =
          jsonUtils.getContentFromStringByKey(responsePost["body"], "token");

      if (newToken != localToken) {
        config.updateInventoryConfig("token", newToken);
        logInfo("Local token updated with server token.");

        return true;
      } else {
        logInfo("Local token matches server token. No update required.");

        return true;
      }
    } else {
      logVerbose(".");
      logError("Token generation failed!");

      return false;
    }
  }

  /// Verify if an inventory already exists on the server.
  Future<void> checkInventoryExist(Map<String, dynamic> body) async {
    String uuid = body['uuid'];
    uuid = uuid.isEmpty ? 'none' : uuid;

    logInfo("Checking if device inventory already exists...");
    // Try to get an existing inventory

    // API call
    String url = baseUrl + "/asset/bases/?uuid=$uuid";
    dynamic responseGet = await sendApiRequest("GET", url);

    logVerbose(responseGet["message"]);

    if (responseGet != null &&
        responseGet["status_code"] == 200 &&
        responseGet["body"].contains(uuid)) {
      logInfo("Existing inventory found!");

      assetID = jsonDecode(responseGet["body"])[0]?["id"];
      inventoryCheck = true;
    } else {
      logInfo("No existing inventory found.");

      assetID = -1;
      inventoryCheck = false;
    }
  }

  /// Check if config file exists and save it if not
  Future<void> checkAndApplyConfig() async {
    logInfo("Loading local configuration...");

    // Get data from core.json file
    List<dynamic> localConfig = config.getCoreConfigs();

    logInfo("Verifying local configuration...");

    // If the config file is empty, we get an existing config from the API and save it locally
    if (localConfig.isEmpty) {
      logInfo("Local configuration not found! Creating a new one...");

      await getConfig();
    } else {
      logInfo("Local configuration found.");

      await checkAndApplyConfigUpdate();
    }
  }

  /// Save the server configs in config/core.json
  Future<void> getConfig() async {
    // Save the existing config locally
    List<dynamic> config = await getRemoteConfig();

    if (config.isEmpty) {
      logError("Unable to retrieve remote configuration.");
    } else {
      this.config.setCore(encoder.convert(config));

      logInfo("Remote configuration saved locally.");
      logger.serverLogger(assetID, 9, "Remote configuration saved locally.");
    }
  }

  /// Get remote config
  Future<List<dynamic>> getRemoteConfig() async {
    logInfo("Retrieving remote configuration...");
    // Try to get an existing config from the server to save it in the core.json file

    // API call
    String url = baseUrl + "/asset/configs/";
    dynamic responseGet = await sendApiRequest("GET", url);

    logVerbose(responseGet["message"]);

    if (responseGet != null && responseGet["status_code"] == 200) {
      logInfo("Remote configuration found.");

      // Save the existing config locally
      List<dynamic> config = json.decode(responseGet["body"]);

      return json.decode(encoder.convert(config));
    } else {
      logError("Remote configuration not found.");
      logger.serverLogger(assetID, 10, "Remote configuration not found.");

      return [];
    }
  }

  /// Check if the config file has been updated and save it if necessary
  Future<void> checkAndApplyConfigUpdate() async {
    // Get data from core.json file
    List<dynamic> localConfig = config.getCoreConfigs();

    // Get remote config
    List<dynamic> remoteConfig = await getRemoteConfig();

    // Compare both configs
    if (localConfig.isNotEmpty || remoteConfig.isNotEmpty) {
      logVerbose(localConfig.toString());
      logVerbose(remoteConfig.toString());

      if (localConfig.toString() != remoteConfig.toString()) {
        logInfo(
            "Local configuration differs from the remote configuration. Updating...");

        config.setCore(encoder.convert(remoteConfig));

        logInfo("Local configuration updated.");
        logger.serverLogger(assetID, 9, "Local configuration updated.");
      } else {
        logInfo("Local configuration is up-to-date.");
      }
    } else {
      logError("Unable to retrieve local or remote configuration.");
    }
  }

  /// Get the remote template values to create or update the local template.
  Future<bool> getRemoteTemplate(Map<String, dynamic> body) async {
    // Get templates data
    var remoteInfo, localInfo;

    try {
      remoteInfo = await getRemoteTemplateInfo(body);
      localInfo = getLocalTemplateInfo();
    } catch (e) {
      logError("Unable to retrieve local or remote template: $e");

      return false;
    }

    if (remoteInfo["return"] != "false" || localInfo["return"] != "false") {
      var compareResult = compareTemplate(localInfo, remoteInfo);

      // Depending on result, update the template or not
      if (compareResult == 0) {
        logInfo("Current template is up-to-date.");

        return true;
      } else if (compareResult == 1 || compareResult == 2) {
        // Try to get the remote template to save it locally

        logInfo(
            "Creating or updating local template with the remote version...");

        var id = remoteInfo["id"];
        // API call
        String url = baseUrl + "/templates/$id/?expand=*";
        dynamic responseGet = await sendApiRequest("GET", url);

        logVerbose(responseGet["message"]);

        if (responseGet != null && responseGet["status_code"] == 200) {
          // Save remote template locally
          logInfo("Remote template found.");

          Map<String, dynamic> template = json.decode(responseGet["body"]);
          config.setTemplate(encoder.convert(template));

          logInfo("Remote template saved locally.");
          logger.serverLogger(assetID, 11, "Remote template saved locally.");

          return true;
        } else {
          logError("Remote template not found.");
          logger.serverLogger(assetID, 12, "Remote template not found.");

          return false;
        }
      } else {
        logError("Template comparison failed.");

        return false;
      }
    } else {
      logError("Unable to retrieve local or remote template.");

      return false;
    }
  }

  /// Check if a local template exists.
  bool getLocalTemplate() {
    logInfo("Loading local template...");

    Map<String, dynamic> template = config.getTemplate();
    // Check if the local template exists
    if (template.isNotEmpty ||
        template.values.isNotEmpty ||
        template.keys.isNotEmpty) {
      logInfo("Local template found.");

      return true;
    } else {
      logError("Local template not found");

      return false;
    }
  }

  /// Get the remote template id and last update.
  Future<Map<String, String>> getRemoteTemplateInfo(
      Map<String, dynamic> body) async {
    String uuid = await body['uuid'];
    uuid = uuid.isEmpty ? 'none' : uuid;

    logInfo("Retrieving remote template information...");
    // Try to get remote template info to return it

    // API call
    String url = baseUrl + "/asset/bases/?uuid=" + uuid;
    dynamic responseAsset = await sendApiRequest("GET", url);

    logVerbose(responseAsset["message"]);

    if (responseAsset != null &&
        responseAsset["status_code"] == 200 &&
        jsonDecode(responseAsset["body"]).isNotEmpty) {
      logInfo("Base inventory found.");

      // API call
      String url = baseUrl +
          "/templates/" +
          jsonDecode(responseAsset["body"])[0]['template'].toString() +
          "/?expand=*";
      dynamic responseTemplate = await sendApiRequest("GET", url);

      logVerbose(responseTemplate["message"]);

      if (responseTemplate != null && responseTemplate["status_code"] == 200) {
        // Create info object
        logInfo("Remote template found.");

        return {
          "id": jsonDecode(responseTemplate["body"])['id'].toString(),
          "last_update":
              jsonDecode(responseTemplate["body"])['last_update'].toString(),
          "return": "true",
        };
      } else {
        logError("Remote template not found.");

        return {
          "return": "false",
        };
      }
    } else {
      logError("Asset base not found.");

      return {
        "return": "false",
      };
    }
  }

  /// Get the local template id and last update.
  Map<String, String> getLocalTemplateInfo() {
    Map<String, String> info;

    if (getLocalTemplate()) {
      // Create info object
      var template = config.getTemplate();

      info = {
        "id": template["id"].toString(),
        "last_update": template["last_update"].toString(),
        "return": "true",
      };
    } else {
      info = {
        "return": "false",
      };
    }

    return info;
  }

  /// Compare both templates to know if we need to create or update the local template.
  int compareTemplate(
      Map<String, String> localInfo, Map<String, String> remoteInfo) {
    logInfo("Comparing templates...");

    try {
      // Compare both templates info
      if (remoteInfo["id"] == localInfo["id"]) {
        logInfo("Local template exists on the server.");

        if (remoteInfo["last_update"] == localInfo["last_update"]) {
          logInfo("Local template is up-to-date.");

          return 0;
        } else {
          logInfo("Local template is outdated.");

          return 1;
        }
      } else {
        logInfo("Local template does not exist on the server.");

        return 2;
      }
    } catch (e) {
      logError("Error comparing template info: $e");
      return -1;
    }
  }

  /// Process the template and format template inventory.
  Future<Map<String, dynamic>> processTemplate() async {
    // Get the template from template.json
    var template = config.getTemplate();

    logInfo("Processing template...");

    var value = await getInventoryResult(template, template["os"]);
    var templateInventory;

    // If the value isn't empty, it creates an object with data
    // If not, return an error
    if (value.isNotEmpty) {
      templateInventory = {
        "values": value,
        "return": "true",
      };

      logInfo("Template processed successfully.");
    } else {
      templateInventory = {
        "return": "false",
      };

      logError("Failed to process template. Template is empty.");
    }
    return templateInventory;
  }

  /// Get all informations present in the local [template]
  /// with a [os] verification and format it in json.
  Future<Map<String, dynamic>> getInventoryResult(
      Map<String, dynamic> template, String os) async {
    Map<String, dynamic> inventoryResult = {};
    var format;
    List<dynamic> sections = [];

    try {
      // Check the os platform
      if (os == "LIN") {
        format = linuxFormat;
      } else if (template["os"] == "WIN" && Platform.isWindows) {
        format = windowsFormat;
      } else if (template["os"] == "MAC" && Platform.isMacOS) {
        format = macOSFormat;
      } else {
        logError("Unsupported OS detected.");
      }

      sections = template['sections'];
    } catch (e) {
      logError("Error while assigning format or reading sections: $e");
    }

    if (sections.isNotEmpty) {
      for (var section in sections) {
        Map<String, dynamic> result = await getResult(os, template, section);
        var valueTarget;

        // Choose the retrieval format
        switch (section['retrival_output']) {
          case "TBLE":
            valueTarget = format.getByArray(section["fields"], result);
            break;

          case "JSON":
            if (os == "MAC") {
              valueTarget = format.getByJson(
                  section["fields"], result, section["target"]);
            } else {
              valueTarget = format.getByJson(section["fields"], result);
            }
            break;

          case "PTXT":
            valueTarget = await format.getByPtxt(section["fields"], result);
            break;

          case "REGX":
            valueTarget = format.getByRegx(section["fields"], result);
            break;

          case "GREP":
            valueTarget = format.getByGrep(section["fields"], result);
            break;

          default:
            valueTarget = null;
            break;
        }

        inventoryResult.putIfAbsent(section['name'], () => valueTarget);
      }
    }

    return inventoryResult;
  }

  /// Get the result
  Future<Map<String, dynamic>> getResult(String os,
      Map<String, dynamic> template, Map<String, dynamic> section) async {
    late var command;
    Map<String, dynamic> result = {};
    Map<String, dynamic> main = {};
    Map<String, dynamic> options = {};
    String mainRes;

    try {
      // Check the os platform
      if (os == "LIN") {
        command = this.linuxCommand;
      } else if (template["os"] == "WIN" && Platform.isWindows) {
        command = this.windowsCommand;
      } else if (template["os"] == "MAC" && Platform.isMacOS) {
        command = this.macOSCommand;
      } else {
        logError("Unsupported OS detected.");
      }

      if (section['options'] != null) {
        options = section['options'];
      }

      mainRes = await command.getResult(
          section["target"], section['retrival_method']);
    } catch (e) {
      logError("Unable to get results: $e");
      return result;
    }

    main.putIfAbsent('name', () => section['name']);
    main.putIfAbsent('type', () => section['retrival_output']);
    main.putIfAbsent('options', () => options);
    main.putIfAbsent('result', () => mainRes);
    result.putIfAbsent('main', () => main);

    List<dynamic> test = section['fields'];
    var fieldOver = test.where((element) => element["override_target"]);

    for (var field in fieldOver) {
      Map<String, dynamic> sub = {};
      String res;

      try {
        res = await command.getResult(
            field["new_target"], field['retrival_method']);
      } catch (e) {
        logError("Error processing field override: $e");
        return result;
      }

      sub.putIfAbsent('name', () => field['name']);
      sub.putIfAbsent('type', () => field['retrival_output']);
      sub.putIfAbsent('options', () => field['options']);
      sub.putIfAbsent('result', () => res);
      result.putIfAbsent(field['name'], () => sub);
    }

    return result;
  }

  /// Create or update the inventory and send it to the server.
  Future<void> sendRemoteBaseInventory(Map<String, dynamic> body) async {
    if (inventoryCheck) {
      String uuid = await body['uuid'];
      uuid = uuid.isEmpty ? 'none' : uuid;

      logInfo("Sending base inventory to server...");
      // Try to get the existing inventory
      // If an inventory is retrieved, check its uuid
      // If an uuid exists, update the current inventory or create one if not
      // If not dislay an error message and if there is an error, return query error

      // API call
      String url = baseUrl + "/asset/bases/?uuid=$uuid";
      dynamic responseGet = await sendApiRequest("GET", url);

      logVerbose(responseGet["message"]);

      if (responseGet != null && responseGet["status_code"] == 200) {
        // Check if the uuid exists
        if (responseGet["body"].contains(uuid)) {
          // Update the inventory
          logInfo("Updating inventory...");

          // API call
          String url = baseUrl + "/asset/collection/";
          var convertedValue = jsonEncode(body);
          dynamic responsePut =
              await sendApiRequest("PUT", url, body: convertedValue);

          logVerbose(responsePut["message"]);

          if (responsePut != null && responsePut["status_code"] == 200) {
            logInfo("Inventory updated successfully.");
            logger.serverLogger(assetID, 2, "Inventory updated successfully.");
          } else {
            logError("Inventory update failed.");
            logger.serverLogger(assetID, 5, "Inventory update failed.");
          }
        } else {
          logError("UUID could not be retrieved from base inventory.");
          logger.serverLogger(
              assetID, 5, "UUID could not be retrieved from base inventory.");
        }
      } else {
        logError("Failed to get inventory from server.");
        logger.serverLogger(assetID, 5, "Failed to get inventory from server.");
      }
    } else {
      // Create the inventory
      logInfo("Creating new inventory...");

      // API call
      String url = baseUrl + "/asset/collection/";
      var header = httpUtils.getHeader(config);
      String jsonEncoded = jsonEncode(body);
      dynamic responsePost =
          await sendApiRequest("POST", url, headers: header, body: jsonEncoded);

      logVerbose(responsePost["message"]);

      if (responsePost != null && responsePost["status_code"] == 200) {
        logInfo("Inventory created successfully.");
        logger.serverLogger(assetID, 1, "Inventory created successfully.");
      } else {
        logError("Inventory creation failed.");
        logger.serverLogger(assetID, 5, "Inventory creation failed.");
      }
    }
  }

  /// Update the remote inventory to add template inventory
  Future<void> sendRemoteTemplateInventory(Map<String, dynamic> body) async {
    if (await getRemoteTemplate(body)) {
      var templateInventory = await processTemplate();

      logInfo("Sending template inventory to server...");

      if (templateInventory["return"] != false) {
        logInfo("Retrieving remote base inventory...");

        String uuid = await body['uuid'];
        uuid = uuid.isEmpty ? 'none' : uuid;

        // API call
        String url = baseUrl + "/asset/bases/?uuid=$uuid";
        dynamic responseGet = await sendApiRequest("GET", url);

        logVerbose(responseGet["message"]);

        if (responseGet != null && responseGet["status_code"] == 200) {
          logInfo("Remote base inventory found.");

          // If there is a uuid in the inventory, update the current inventory
          // Else, return an error
          if (responseGet["body"].contains(uuid)) {
            logInfo("Updating base inventory...");

            var content = jsonDecode(responseGet["body"])[0];
            content["template_inventory"] = templateInventory["values"];
            Map<dynamic, dynamic> updatedInventory = {};

            if (config.getCoreConfig("agent", "inventory_checksum")) {
              late var sectionBase64, sectionBytes, sectionJson;
              sectionJson = {};

              content["template_inventory"].keys.forEach((element) {
                sectionBytes = utf8
                    .encode(content["template_inventory"][element].toString());
                sectionBase64 = base64.encode(sectionBytes);
                sectionJson[element] = sectionBase64;
              });

              if (!inventoryBase64.existsSync()) {
                logError("Can't find base64 file, creating one...");
                inventoryBase64.createSync(recursive: true);
                filesUtils.writeFile(inventoryBase64, "{}");
              }

              logInfo("Base64 file found.");
              var fileBase64 = jsonDecode(inventoryBase64.readAsStringSync());

              sectionJson.forEach((newKey, newValue) {
                if (!fileBase64.containsKey(newKey)) {
                  logVerbose(sprintf("%s section added to the inventory.", [newKey]));
                  updatedInventory[newKey] = content["template_inventory"][newKey];
                } else if (fileBase64[newKey] != newValue) {
                  logVerbose(sprintf("%s section will be updated.", [newKey]));
                  updatedInventory[newKey] = content["template_inventory"][newKey];
                } else {
                  logVerbose(sprintf(
                      "%s section has not changed since last inventory.", [newKey]));
                }
              });

              filesUtils.writeFile(
                  inventoryBase64, encoder.convert(sectionJson));
            }

            // API call
            String url = baseUrl + "/asset/sections/?base=$assetID";
            dynamic inventoryExist = await sendApiRequest("GET", url);

            if (inventoryExist != null &&
                inventoryExist["status_code"] == 200) {
              if (config.getCoreConfig("agent", "inventory_checksum")) {
                content["template_inventory"] = updatedInventory;
              }

              // API call
              String url = baseUrl + "/asset/collection/";
              var convertedValue = encoder.convert(content);
              dynamic responsePatch =
                  await sendApiRequest("PATCH", url, body: convertedValue);

              logVerbose(responsePatch["message"]);

              if (responsePatch != null &&
                  responsePatch["status_code"] == 200) {
                logInfo("Template inventory updated successfully.");
                logger.serverLogger(
                    assetID, 4, "Template inventory updated successfully.");
              } else {
                logError("Failed to update template inventory.");
                logger.serverLogger(
                    assetID, 6, "Failed to update template inventory.");
              }
            } else {
              // API call
              String url = baseUrl + "/asset/collection/";
              var convertedValue = encoder.convert(content);
              dynamic responsePut =
                  await sendApiRequest("PUT", url, body: convertedValue);

              logVerbose(responsePut["message"]);

              if (responsePut != null && responsePut["status_code"] == 200) {
                logInfo("Template inventory updated successfully.");
                logger.serverLogger(
                    assetID, 6, "Template inventory updated successfully.");
              } else {
                logError("Failed to update template inventory.");
              }
            }
          } else {
            logError("Missing UUID in base inventory.");
            logger.serverLogger(assetID, 6, "Missing UUID in base inventory.");
          }
        } else {
          logError("Failed to retrieve base inventory from server.");
          logger.serverLogger(
              assetID, 6, "Failed to retrieve base inventory from server.");
        }
      } else {
        logError("Failed to process template.");
      }
    } else {
      logError("Failed to get remote template.");
    }
  }

  /// Create a local inventory in the JSON format.
  Future<void> sendLocalBaseInventory(Map<String, dynamic> body) async {
    logInfo("Creating base inventory file...");
    logInfo("Writing base inventory locally...");

    // Create a file to save the new inventory
    try {
      await inventoryFile.create(recursive: true);
      var encoder = await JsonEncoder.withIndent("\t");
      // Write the new inventory inside
      filesUtils.writeFile(inventoryFile, encoder.convert(body));

      logInfo(sprintf("New base inventory created in %s", [inventoryFileName]));
    } catch (e) {
      logError("Error getting inventory: $e");
    }
  }

  /// Update the local inventory to add template inventory
  Future<void> sendLocalTemplateInventory() async {
    logInfo("Adding template inventory to local inventory...");

    if (getLocalTemplate()) {
      var templateInventory = await processTemplate();

      if (templateInventory["return"] != false) {
        // Get the local inventory
        var content = jsonDecode(inventoryFile.readAsStringSync());
        content["template_inventory"] = templateInventory["values"];

        logVerbose(content["template_inventory"].toString());

        try {
          // Write into inventory file
          filesUtils.writeFile(inventoryFile, encoder.convert(content));

          logInfo("Template inventory added to base inventory!");
        } catch (e) {
          logError("Error writing to file: $e");
        }
      } else {
        logError("Failed to process template.");
      }
    } else {
      logError("Failed to retrieve local template.");
    }
  }

  Future<dynamic> sendApiRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    try {
      var uri = Uri.parse(url);
      var h = headers ?? httpUtils.getHeader(config);

      switch (method.toUpperCase()) {
        case "GET":
          return await httpUtils.get(uri, h);

        case "POST":
          return await httpUtils.post(uri, h, body);

        case "PUT":
          return await httpUtils.put(uri, h, body);

        case "PATCH":
          return await httpUtils.patch(uri, h, body);

        default:
          logError("Unsupported HTTP method: $method");

          return null;
      }
    } catch (e) {
      logError("API $method call failed: $e");

      return null;
    }
  }

  void logInfo(String msg) => logger.info(runtimeType.toString(), msg);
  void logError(String msg) => logger.error(runtimeType.toString(), msg);
  void logVerbose(String msg) => logger.verbose(runtimeType.toString(), msg);
}
