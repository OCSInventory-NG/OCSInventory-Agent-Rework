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

import 'package:ocs_agent/core/inventory/commands.dart';
import 'package:ocs_agent/core/inventory/format.dart';

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
  late Commands commands;
  late Format format;

  late var url;
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
    this.commands,
    this.format,
  ) {
    String? dataDirectory;

    try {
      dataDirectory = config.getInventoryConfig("data_directory");
      this.url = config.getInventoryConfig("url");
    } catch (e) {
      logger.error(
          this.runtimeType.toString(), "Missing configuration fields: $e");
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
    String username, password, localToken;
    dynamic responseGet;

    try {
      username = config.getInventoryConfig("username");
      password = config.getInventoryConfig("password");

      // Optional retrieval of the token (can be empty on first run)
      localToken = config.getInventoryConfig("token");

      await generateToken(username, password, localToken);
    } catch (e) {
      logger.verbose(this.runtimeType.toString(),
          "Check username or password in the configuration file.");
      logger.error(this.runtimeType.toString(),
          "Configuration error when generating token: $e");
    }

    // Check OCS API status
    logger.info(this.runtimeType.toString(), "Checking API availability...");

    try {
      responseGet =
          await httpUtils.get(Uri.parse(url), httpUtils.getHeader(config));

      if (responseGet?["status_code"] == 200) {
        logger.verbose(this.runtimeType.toString(), responseGet["message"]);
        logger.info(this.runtimeType.toString(), "API is online!");

        return true;
      } else {
        logger.error(this.runtimeType.toString(), "API connection failed!");
      }
    } catch (e) {
      logger.error(this.runtimeType.toString(),
          "Exception during API availibility check: $e");
    }

    return false;
  }

  /// Send to API the [username] and [password] and save the token retreived in inventory.json.
  Future<bool> generateToken(
      String username, String password, String localToken) async {
    dynamic responsePost;
    var newToken;

    // API call
    logger.info(this.runtimeType.toString(), "Generating token...");

    try {
      responsePost = await httpUtils.post(
          Uri.parse("$url/api-auth/token"),
          {HttpHeaders.contentTypeHeader: 'application/json'},
          jsonEncode({'username': username, 'password': password}));
    } catch (e) {
      logger.error(
          this.runtimeType.toString(), "Exception during API call: $e");
    }

    if (responsePost?["status_code"] == 200) {
      logger.verbose(this.runtimeType.toString(), responsePost["message"]);
      logger.info(this.runtimeType.toString(), "Token retrieved successfully.");

      // Get the token from the response body and compare with the local token
      // If tokens are not the same, replace the local token with the server one
      newToken =
          jsonUtils.getContentFromStringByKey(responsePost["body"], "token");

      if (newToken != localToken) {
        config.updateInventoryConfig("token", newToken);
        logger.info(this.runtimeType.toString(),
            "Local token updated with server token.");
      } else {
        logger.info(this.runtimeType.toString(),
            "Local token matches server token. No update required.");
      }

      return true;
    } else {
      logger.verbose(
          this.runtimeType.toString(), "Unable to get token from server.");
      logger.error(this.runtimeType.toString(), "Token generation failed!");

      return false;
    }
  }

  /// Verify if an inventory already exists on the server.
  Future<void> checkInventoryExist(Map<String, dynamic> body) async {
    String uuid;
    dynamic responseGet;

    // API call
    logger.info(this.runtimeType.toString(),
        "Checking if device inventory already exists...");
    uuid = body['uuid'].isEmpty ? 'none' : body['uuid'];

    try {
      responseGet = await httpUtils.get(
          Uri.parse("$url/asset/bases/?uuid=$uuid"),
          httpUtils.getHeader(config));
      logger.verbose(this.runtimeType.toString(), responseGet["message"]);
    } catch (e) {
      logger.error(
          this.runtimeType.toString(), "Exception during API call: $e");
    }

    if (responseGet?["status_code"] == 200 &&
        responseGet["body"].contains(uuid)) {
      logger.info(this.runtimeType.toString(), "Existing inventory found!");
      assetID = jsonDecode(responseGet["body"])[0]?["id"];
      inventoryCheck = true;
    } else {
      logger.info(this.runtimeType.toString(), "No existing inventory found.");
      assetID = -1;
      inventoryCheck = false;
    }
  }

  /// Check if config file exists and save it if not
  Future<void> checkAndApplyConfig() async {
    List<dynamic> localConfig;

    logger.info(this.runtimeType.toString(), "Loading local configuration...");

    // Get data from core.json file
    localConfig = config.getCoreConfigs();

    logger.info(
        this.runtimeType.toString(), "Verifying local configuration...");

    // If the config file is empty, we get an existing config from the API and save it locally
    if (localConfig.isEmpty) {
      logger.info(this.runtimeType.toString(),
          "Local configuration not found! Creating a new one...");
      await getConfig();
    } else {
      logger.info(this.runtimeType.toString(), "Local configuration found.");
      await checkAndApplyConfigUpdate();
    }
  }

  /// Save the server configs in config/core.json
  Future<void> getConfig() async {
    List<dynamic> remoteConfig = await getRemoteConfig();

    if (remoteConfig.isEmpty) {
      logger.error(this.runtimeType.toString(),
          "Unable to retrieve remote configuration.");
    } else {
      logger.info(
          this.runtimeType.toString(), "Remote configuration saved locally.");
      logger.serverLogger(assetID, 9, "Remote configuration saved locally.");
      this.config.setCore(encoder.convert(remoteConfig));
    }
  }

  /// Get remote config from the server to save it in the core.json file
  Future<List<dynamic>> getRemoteConfig() async {
    dynamic responseGet;
    List<dynamic> remoteConfig = [];

    // API call
    logger.info(
        this.runtimeType.toString(), "Retrieving remote configuration...");

    try {
      responseGet = await httpUtils.get(
          Uri.parse("$url/asset/configs/"), httpUtils.getHeader(config));
      logger.verbose(this.runtimeType.toString(), responseGet["message"]);
    } catch (e) {
      logger.error(
          this.runtimeType.toString(), "Exception during API call: $e");
    }

    if (responseGet?["status_code"] == 200) {
      logger.info(this.runtimeType.toString(), "Remote configuration found.");

      // Save the existing config locally
      remoteConfig = json.decode(responseGet["body"]);

      return json.decode(encoder.convert(remoteConfig));
    } else {
      logger.error(
          this.runtimeType.toString(), "Remote configuration not found.");
      logger.serverLogger(assetID, 10, "Remote configuration not found.");

      return remoteConfig;
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
      logger.verbose(this.runtimeType.toString(), localConfig.toString());
      logger.verbose(this.runtimeType.toString(), remoteConfig.toString());

      if (localConfig.toString() != remoteConfig.toString()) {
        logger.info(this.runtimeType.toString(),
            "Local configuration differs from the remote configuration. Updating...");

        config.setCore(encoder.convert(remoteConfig));

        logger.info(
            this.runtimeType.toString(), "Local configuration updated.");
        logger.serverLogger(assetID, 9, "Local configuration updated.");
      } else {
        logger.info(
            this.runtimeType.toString(), "Local configuration is up-to-date.");
      }
    } else {
      logger.error(this.runtimeType.toString(),
          "Unable to retrieve local or remote configuration.");
    }
  }

  /// Get the remote template values to create or update the local template.
  Future<bool> getRemoteTemplate(Map<String, dynamic> body) async {
    // Get templates data
    var remoteInfo, localInfo, id;
    int compareResult;
    dynamic responseGet;
    Map<String, dynamic> template;

    try {
      remoteInfo = await getRemoteTemplateInfo(body);
      localInfo = getLocalTemplateInfo();
    } catch (e) {
      logger.error(this.runtimeType.toString(),
          "Unable to retrieve local or remote template: $e");

      return false;
    }

    if (remoteInfo["return"] != false || localInfo["return"] != false) {
      compareResult = compareTemplate(localInfo, remoteInfo);

      // Depending on result, update the template or not
      if (compareResult == 0) {
        logger.info(
            this.runtimeType.toString(), "Current template is up-to-date.");

        return true;
      } else if (compareResult == 1 || compareResult == 2) {
        // Try to get the remote template to save it locally
        id = remoteInfo["id"];

        // API call
        logger.info(this.runtimeType.toString(),
            "Creating or updating local template with the remote version...");

        try {
          responseGet = await httpUtils.get(
              Uri.parse("$url/templates/$id/?expand=*"),
              httpUtils.getHeader(config));
          logger.verbose(this.runtimeType.toString(), responseGet["message"]);
        } catch (e) {
          logger.error(
              this.runtimeType.toString(), "Exception during API call: $e");
        }

        if (responseGet?["status_code"] == 200) {
          // Save remote template locally
          logger.info(this.runtimeType.toString(), "Remote template found.");

          template = json.decode(responseGet["body"]);
          config.setTemplate(encoder.convert(template));

          logger.info(
              this.runtimeType.toString(), "Remote template saved locally.");
          logger.serverLogger(assetID, 11, "Remote template saved locally.");

          return true;
        } else {
          logger.error(
              this.runtimeType.toString(), "Remote template not found.");
          logger.serverLogger(assetID, 12, "Remote template not found.");

          return false;
        }
      }
    } else {
      // If either template is missing, we need to create a new one
      logger.info(this.runtimeType.toString(), "Creating new template...");

      try {
        responseGet = await httpUtils.get(
            Uri.parse("$url/templates/$id/?expand=*"),
            httpUtils.getHeader(config));
      } catch (e) {
        logger.error(
            this.runtimeType.toString(), "Exception during API call: $e");
      }

      if (responseGet?["status_code"] == 200) {
        template = json.decode(responseGet["body"]);

        if (!template.containsKey("id") ||
            !template.containsKey("last_update")) {
          logger.error(this.runtimeType.toString(),
              "Invalid template structure received from server");
          return false;
        }

        config.setTemplate(encoder.convert(template));
        logger.info(
            this.runtimeType.toString(), "New template created successfully.");

        return true;
      }
    }

    return false;
  }

  /// Check if a local template exists.
  bool getLocalTemplate() {
    Map<String, dynamic> template;

    logger.info(this.runtimeType.toString(), "Loading local template...");

    template = config.getTemplate();
    // Check if the local template exists
    if (template.isNotEmpty ||
        template.values.isNotEmpty ||
        template.keys.isNotEmpty) {
      logger.info(this.runtimeType.toString(), "Local template found.");

      return true;
    } else {
      logger.error(this.runtimeType.toString(), "Local template not found");

      return false;
    }
  }

  /// Get the remote template id and last update.
  Future<Map<String, String>> getRemoteTemplateInfo(
      Map<String, dynamic> body) async {
    String uuid;
    dynamic assetMap, templateMap;
    dynamic responseAsset, responseTemplate;

    // API call
    logger.info(this.runtimeType.toString(),
        "Retrieving remote template information...");
    uuid = body['uuid'].isNotEmpty ? body['uuid'] : 'none';

    try {
      responseAsset = await httpUtils.get(
          Uri.parse("$url/asset/bases/?uuid=$uuid"),
          httpUtils.getHeader(config));
      logger.verbose(this.runtimeType.toString(), responseAsset["message"]);

      assetMap = jsonDecode(responseAsset?["body"]);
    } catch (e) {
      logger.error(
          this.runtimeType.toString(), "Exception during API call: $e");
    }

    if (responseAsset?["status_code"] == 200 && assetMap.isNotEmpty) {
      // API call
      logger.info(this.runtimeType.toString(), "Base inventory found.");

      try {
        responseTemplate = await httpUtils.get(
            Uri.parse(
                "$url/templates/${assetMap[0]['template'].toString()}/?expand=*"),
            httpUtils.getHeader(config));
        logger.verbose(
            this.runtimeType.toString(), responseTemplate["message"]);
        templateMap = jsonDecode(responseTemplate?["body"]);
      } catch (e) {
        logger.error(
            this.runtimeType.toString(), "Exception during API call: $e");
      }

      if (responseTemplate?["status_code"] == 200) {
        // Create info object
        logger.info(this.runtimeType.toString(), "Remote template found.");

        return {
          "id": templateMap['id'].toString(),
          "last_update": templateMap['last_update'].toString(),
          "return": "true",
        };
      } else {
        logger.error(this.runtimeType.toString(), "Remote template not found.");
      }
    } else {
      logger.error(this.runtimeType.toString(), "Asset base not found.");
    }

    return {"return": "false"};
  }

  /// Get the local template id and last update.
  Map<String, String> getLocalTemplateInfo() {
    bool localTemplateFound = getLocalTemplate();
    Map<String, dynamic> template = config.getTemplate();
    Map<String, String> result = {"return": localTemplateFound.toString()};

    if (localTemplateFound) {
      result["id"] = template["id"].toString();
      result["last_update"] = template["last_update"].toString();
    }

    return result;
  }

  /// Compare both templates based on [localInfo] and [remoteInfo] to create or update the local template.
  int compareTemplate(
      Map<String, String> localInfo, Map<String, String> remoteInfo) {
    Map<String, dynamic> localTemplate = config.getTemplate();
    Map<String, dynamic> remoteTemplate =
        json.decode(remoteInfo["content"] ?? "{}");

    logger.info(this.runtimeType.toString(), "Comparing templates...");

    // Compare both templates info
    if (localInfo["return"] == "false" || remoteInfo["return"] == "false") {
      logger.info(this.runtimeType.toString(),
          "One of the templates is missing, update required.");
      return 2;
    }

    if (remoteInfo["id"]?.trim() != localInfo["id"]?.trim()) {
      logger.info(this.runtimeType.toString(),
          "Template IDs differ - Local: ${localInfo["id"]}, Remote: ${remoteInfo["id"]}");
      return 2;
    }

    if (remoteInfo["last_update"]?.trim() != localInfo["last_update"]?.trim()) {
      logger.info(this.runtimeType.toString(),
          "Template versions differ - Local: ${localInfo["last_update"]}, Remote: ${remoteInfo["last_update"]}");
      return 1;
    }

    if (localTemplate.toString() != remoteTemplate.toString()) {
      logger.info(this.runtimeType.toString(),
          "Template content differs, update required.");
      return 1;
    }

    logger.info(this.runtimeType.toString(),
        "Templates are identical, no update needed.");
    return 0;
  }

  /// Process the template and format template inventory.
  Future<Map<String, dynamic>> processTemplate() async {
    Map<String, dynamic> template, value;
    bool processValid;

    logger.info(this.runtimeType.toString(), "Processing template...");

    template = config.getTemplate();
    value = await getInventoryResult(template, template["os"]);
    processValid = value.isNotEmpty;

    if (processValid) {
      logger.info(
          this.runtimeType.toString(), "Template processed successfully.");
    } else {
      logger.warning(this.runtimeType.toString(),
          "Failed to process template. Template is empty.");
    }

    return {
      if (processValid) "values": value,
      "return": processValid,
    };
  }

  /// Get all informations present in the local [template]
  /// with a [os] verification and format it in json.
  Future<Map<String, dynamic>> getInventoryResult(
      Map<String, dynamic> template, String os) async {
    List<dynamic> sections = [];
    Map<String, dynamic> result = {};
    Map<String, dynamic> inventoryResult = {};
    var valueTarget;

    try {
      sections = template['sections'];
    } catch (e) {
      logger.error(this.runtimeType.toString(),
          "Error while assigning format or reading sections: $e");
    }

    if (sections.isNotEmpty) {
      for (var section in sections) {
        result = await getResult(os, template, section);

        switch (section['retrival_output']) {
          case "JSON":
            if (os == "MAC") {
              valueTarget = format.getByMethod(section['retrival_output'],
                  section["fields"], result, section["target"]);
            } else {
              valueTarget = format.getByMethod(
                  section['retrival_output'], section["fields"], result);
            }
            break;

          case "TBLE":
          case "PTXT":
          case "REGX":
          case "GREP":
            valueTarget = format.getByMethod(
                section['retrival_output'], section["fields"], result);
            break;

          default:
            logger.warning(
                this.runtimeType.toString(), "Retrival format unknown.");
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
    Map<String, dynamic> options = section['options'] ?? {};
    String mainRes, res;
    Map<String, dynamic> result = {};
    Map<String, dynamic> main = {};
    Map<String, dynamic> sub = {};
    List<dynamic> fields = section['fields'] ?? [];
    var fieldOver;

    try {
      mainRes = await this
          .commands
          .getResult(section['retrival_method'], section["target"]);
    } catch (e) {
      logger.warning(this.runtimeType.toString(),
          "Unable to get results for ${section["target"]}: $e");

      return result;
    }

    main.putIfAbsent('name', () => section['name']);
    main.putIfAbsent('type', () => section['retrival_output']);
    main.putIfAbsent('options', () => options);
    main.putIfAbsent('result', () => mainRes);
    result.putIfAbsent('main', () => main);

    fieldOver = fields.where((element) => element["override_target"]);

    for (var field in fieldOver) {
      try {
        res = await commands.getResult(
            field['retrival_method'], field["new_target"]);
      } catch (e) {
        logger.warning(
            this.runtimeType.toString(), "Error processing field override: $e");

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
    String uuid;
    dynamic responseGet, responsePut, responsePost;

    if (inventoryCheck) {
      // Try to get the existing inventory
      // If an inventory is retrieved, check its uuid
      // If an uuid exists, update the current inventory or create one if not
      // If not dislay an error message and if there is an error, return query error

      // API call
      logger.info(
          this.runtimeType.toString(), "Sending base inventory to server...");
      uuid = body['uuid'].isEmpty ? 'none' : body['uuid'];

      try {
        responseGet = await httpUtils.get(
            Uri.parse("$url/asset/bases/?uuid=$uuid"),
            httpUtils.getHeader(config));
        logger.verbose(this.runtimeType.toString(), responseGet["message"]);
      } catch (e) {
        logger.error(
            this.runtimeType.toString(), "Exception during API call: $e");
      }

      if (responseGet?["status_code"] == 200) {
        // Check if the uuid exists
        if (responseGet["body"].contains(uuid)) {
          // API call
          logger.info(this.runtimeType.toString(), "Updating inventory...");

          try {
            responsePut = await httpUtils.put(
                Uri.parse("$url/asset/collection/"),
                httpUtils.getHeader(config),
                jsonEncode(body));
            logger.verbose(this.runtimeType.toString(), responsePut["message"]);
          } catch (e) {
            logger.error(
                this.runtimeType.toString(), "Exception during API call: $e");
          }

          if (responsePut?["status_code"] == 200) {
            logger.info(
                this.runtimeType.toString(), "Inventory updated successfully.");
            logger.serverLogger(assetID, 2, "Inventory updated successfully.");
          } else {
            logger.error(
                this.runtimeType.toString(), "Inventory update failed.");
            logger.serverLogger(assetID, 5, "Inventory update failed.");
          }
        } else {
          logger.error(this.runtimeType.toString(),
              "UUID could not be retrieved from base inventory.");
          logger.serverLogger(
              assetID, 5, "UUID could not be retrieved from base inventory.");
        }
      } else {
        logger.error(this.runtimeType.toString(),
            "Failed to get inventory from server.");
        logger.serverLogger(assetID, 5, "Failed to get inventory from server.");
      }
    } else {
      // API call
      try {
        responsePost = await httpUtils.post(Uri.parse("$url/asset/collection/"),
            httpUtils.getHeader(config), jsonEncode(body));
        logger.verbose(this.runtimeType.toString(), responsePost["message"]);
      } catch (e) {
        logger.error(
            this.runtimeType.toString(), "Exception during API call: $e");
      }

      if (responsePost?["status_code"] == 200) {
        logger.info(
            this.runtimeType.toString(), "Inventory created successfully.");
        logger.serverLogger(assetID, 1, "Inventory created successfully.");
      } else {
        logger.error(this.runtimeType.toString(), "Inventory creation failed.");
        logger.serverLogger(assetID, 5, "Inventory creation failed.");
      }
    }
  }

  /// Update the remote inventory to add template inventory
  Future<void> sendRemoteTemplateInventory(Map<String, dynamic> body) async {
    String uuid;
    dynamic responseGet, inventoryExist, responsePatch, responsePut;
    Map<dynamic, dynamic> updatedInventory = {};
    late var templateInventory,
        content,
        sectionBase64,
        sectionBytes,
        sectionJson;

    if (await getRemoteTemplate(body)) {
      templateInventory = await processTemplate();

      logger.info(this.runtimeType.toString(),
          "Sending template inventory to server...");

      if (templateInventory["return"]) {
        // API call
        logger.info(
            this.runtimeType.toString(), "Retrieving remote base inventory...");
        uuid = body['uuid'].isEmpty ? 'none' : body['uuid'];

        try {
          responseGet = await httpUtils.get(
              Uri.parse("$url/asset/bases/?uuid=$uuid"),
              httpUtils.getHeader(config));
          logger.verbose(this.runtimeType.toString(), responseGet["message"]);
        } catch (e) {
          logger.error(
              this.runtimeType.toString(), "Exception during API call: $e");
        }

        if (responseGet?["status_code"] == 200) {
          logger.info(
              this.runtimeType.toString(), "Remote base inventory found.");

          // If there is a uuid in the inventory, update the current inventory
          // Else, return an error
          if (responseGet["body"].contains(uuid)) {
            logger.info(
                this.runtimeType.toString(), "Updating base inventory...");

            content = jsonDecode(responseGet["body"])[0];
            content["template_inventory"] = templateInventory["values"];

            if (config.getCoreConfig("agent", "inventory_checksum")) {
              sectionJson = {};

              content["template_inventory"].keys.forEach((element) {
                sectionBytes = utf8
                    .encode(content["template_inventory"][element].toString());
                sectionBase64 = base64.encode(sectionBytes);
                sectionJson[element] = sectionBase64;
              });

              if (!inventoryBase64.existsSync()) {
                logger.info(this.runtimeType.toString(),
                    "Can't find base64 file, creating one...");
                inventoryBase64.createSync(recursive: true);
                filesUtils.writeFile(inventoryBase64, "{}");
              }

              logger.info(this.runtimeType.toString(), "Base64 file found.");
              var fileBase64 = jsonDecode(inventoryBase64.readAsStringSync());

              sectionJson.forEach((newKey, newValue) {
                if (!fileBase64.containsKey(newKey)) {
                  logger.verbose(this.runtimeType.toString(),
                      sprintf("%s section added to the inventory.", [newKey]));
                  updatedInventory[newKey] =
                      content["template_inventory"][newKey];
                } else if (fileBase64[newKey] != newValue) {
                  logger.verbose(this.runtimeType.toString(),
                      sprintf("%s section will be updated.", [newKey]));
                  updatedInventory[newKey] =
                      content["template_inventory"][newKey];
                } else {
                  logger.verbose(
                      this.runtimeType.toString(),
                      sprintf(
                          "%s section has not changed since last inventory.",
                          [newKey]));
                }
              });

              filesUtils.writeFile(
                  inventoryBase64, encoder.convert(sectionJson));
            }

            // API call
            try {
              inventoryExist = await httpUtils.get(
                  Uri.parse("$url/asset/sections/?base=$assetID"),
                  httpUtils.getHeader(config));
            } catch (e) {
              logger.error(
                  this.runtimeType.toString(), "Exception during API call: $e");
            }

            if (inventoryExist?["status_code"] == 200) {
              if (config.getCoreConfig("agent", "inventory_checksum")) {
                content["template_inventory"] = updatedInventory;
              }

              // API call
              try {
                responsePatch = await httpUtils.patch(
                    Uri.parse("$url/asset/collection/"),
                    httpUtils.getHeader(config),
                    encoder.convert(content));
                logger.verbose(
                    this.runtimeType.toString(), responsePatch["message"]);
              } catch (e) {
                logger.error(this.runtimeType.toString(),
                    "Exception during API call: $e");
              }

              if (responsePatch?["status_code"] == 200) {
                logger.info(this.runtimeType.toString(),
                    "Template inventory updated successfully.");
                logger.serverLogger(
                    assetID, 4, "Template inventory updated successfully.");
              } else {
                logger.error(this.runtimeType.toString(),
                    "Failed to update template inventory.");
                logger.serverLogger(
                    assetID, 6, "Failed to update template inventory.");
              }
            } else {
              // API call
              try {
                responsePut = await httpUtils.put(
                    Uri.parse("$url/asset/collection/"),
                    httpUtils.getHeader(config),
                    encoder.convert(content));
                logger.verbose(
                    this.runtimeType.toString(), responsePut["message"]);
              } catch (e) {
                logger.error(this.runtimeType.toString(),
                    "Exception during API call: $e");
              }

              if (responsePut?["status_code"] == 200) {
                logger.info(this.runtimeType.toString(),
                    "Template inventory updated successfully.");
                logger.serverLogger(
                    assetID, 6, "Template inventory updated successfully.");
              } else {
                logger.error(this.runtimeType.toString(),
                    "Failed to update template inventory.");
              }
            }
          } else {
            logger.error(
                this.runtimeType.toString(), "Missing UUID in base inventory.");
            logger.serverLogger(assetID, 6, "Missing UUID in base inventory.");
          }
        } else {
          logger.error(this.runtimeType.toString(),
              "Failed to retrieve base inventory from server.");
          logger.serverLogger(
              assetID, 6, "Failed to retrieve base inventory from server.");
        }
      } else {
        logger.error(
            this.runtimeType.toString(), "Failed to process template.");
      }
    } else {
      logger.error(
          this.runtimeType.toString(), "Failed to get remote template.");
    }
  }

  /// Create a local inventory in the JSON format.
  Future<void> sendLocalBaseInventory(Map<String, dynamic> body) async {
    var encoder;

    logger.info(this.runtimeType.toString(), "Creating base inventory file...");
    logger.info(
        this.runtimeType.toString(), "Writing base inventory locally...");

    // Create a file to save the new inventory
    try {
      await inventoryFile.create(recursive: true);
      encoder = await JsonEncoder.withIndent("\t");

      // Write the new inventory inside
      filesUtils.writeFile(inventoryFile, encoder.convert(body));
      logger.info(this.runtimeType.toString(),
          sprintf("New base inventory created in %s", [inventoryFileName]));
    } catch (e) {
      logger.error(this.runtimeType.toString(), "Error getting inventory: $e");
    }
  }

  /// Update the local inventory to add template inventory
  Future<void> sendLocalTemplateInventory() async {
    var templateInventory;
    var content;

    logger.info(this.runtimeType.toString(),
        "Adding template inventory to local inventory...");

    if (getLocalTemplate()) {
      templateInventory = await processTemplate();

      if (templateInventory["return"]) {
        // Get the local inventory
        content = jsonDecode(inventoryFile.readAsStringSync());
        content["template_inventory"] = templateInventory["values"];

        logger.verbose(this.runtimeType.toString(),
            content["template_inventory"].toString());

        try {
          // Write into inventory file
          filesUtils.writeFile(inventoryFile, encoder.convert(content));

          logger.info(this.runtimeType.toString(),
              "Template inventory added to base inventory!");
        } catch (e) {
          logger.error(
              this.runtimeType.toString(), "Error writing to file: $e");
        }
      } else {
        logger.error(
            this.runtimeType.toString(), "Failed to process template.");
      }
    } else {
      logger.error(
          this.runtimeType.toString(), "Failed to retrieve local template.");
    }
  }
}
