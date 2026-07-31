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
import 'dart:convert';
import 'dart:io' show File, Platform, exit, stdout;
import 'package:sprintf/sprintf.dart';
import 'package:args/args.dart';

// Common imports
import 'package:ocsinventory_agent/core/common/files_utils.dart';
import 'package:ocsinventory_agent/core/common/http_utils.dart';
import 'package:ocsinventory_agent/core/common/json_utils.dart';

// Core imports
import 'package:ocsinventory_agent/core/config.dart';
import 'package:ocsinventory_agent/core/log.dart';

import 'package:ocsinventory_agent/core/inventory/linux/baseLinux.dart';
import 'package:ocsinventory_agent/core/inventory/macos/baseMacOS.dart';
import 'package:ocsinventory_agent/core/inventory/windows/baseWindows.dart';

import 'package:ocsinventory_agent/core/inventory/commands.dart';
import 'package:ocsinventory_agent/core/inventory/format.dart';

// Modules imports
import 'package:ocsinventory_agent/core/inventory.dart';
import 'package:ocsinventory_agent/core/deployment.dart';
import 'package:ocsinventory_agent/core/daemon.dart';

/// In this main section we send the [body] to the asset/bases endpoint
void main(List<String> args) async {
  // Initiate the parser for the arguments
  ArgParser parser = ArgParser();
  ArgResults allArgs;
  // Initiate main core
  late Config config;

  // Add the arguments options
  parser.addOption("log_file",
      abbr: "f",
      help: "Enable or disable logging to a file",
      valueHelp: "true/false",
      defaultsTo: "false");
  parser.addOption("mode",
      abbr: "m",
      help: "Specify the agent's execution mode",
      valueHelp:
          "0: Installer mode 1: Remote with template 2: Remote without template 3: Local with template 4: Local without template",
      defaultsTo: "1");
  parser.addOption("password",
      abbr: "p", help: "Password", valueHelp: "password", defaultsTo: "admin");
  parser.addOption("username",
      abbr: "u", help: "Username", valueHelp: "username", defaultsTo: "admin");
  parser.addOption("url",
      abbr: "s",
      help: "URL to the OCS server",
      valueHelp: "http://SERVER_IP:PORT",
      defaultsTo: "http://ocsinventory-server:port");
  parser.addOption("data_directory",
      abbr: "d",
      help: "Inventory directory path",
      valueHelp: "/path_to_inventory_data/folder-name",
      defaultsTo: "inventory");
  parser.addOption("log_file_path",
      abbr: "l",
      help: "Log file path",
      valueHelp: "/path_to_log_file/file-name.log",
      defaultsTo: "ocs-agent.log");
  parser.addOption("log_level",
      abbr: "v",
      help: "Log verbosity level",
      valueHelp: "0: Error 1: Warning 2: Info 3: Verbose",
      defaultsTo: "2");
  parser.addOption("certificate",
      abbr: "c",
      help: "SSL certificate path",
      valueHelp: "/path_to_certificate_file/cert.pem",
      defaultsTo: "/etc/ocsinventory-agent/ocsinventory-agent.pem");
  parser.addOption("bypass-certificate",
      abbr: "b",
      help: "Bypass certificate validation",
      valueHelp: "true/false",
      defaultsTo: "false");
  parser.addOption("service",
      help: "Check if the agent is running as a service",
      valueHelp: "Used only by the daemon",
      defaultsTo: "false");
  parser.addOption("overwrite_config",
      help: "overwrite_config",
      valueHelp: "Overwrite the configuration file if true, default to false",
      defaultsTo: "false");
  parser.addOption("execution_timeout",
      abbr: "t",
      help: "execution_timeout",
      valueHelp: "Maximum time (in seconds) a single inventory command can run before being killed",
      defaultsTo: "120");
  parser.addFlag("help",
      abbr: "h", help: "Display this help message", negatable: false);

  try {
    allArgs = parser.parse(args);
  } on ArgParserException catch (ex) {
    stdout.writeln("Error: Failed to parse arguments.");

    stdout.writeln(ex.message);
    stdout.writeln(parser.usage);
    exit(1);
  } catch (ex) {
    stdout.writeln("Error: An issue occurred while parsing arguments.");
    stdout.writeln(ex);
    stdout.writeln(parser.usage);
    exit(1);
  }

  if (allArgs.wasParsed("help")) {
    stdout.writeln(parser.usage);
    return;
  }

  late final String configDirectory;
  if (Platform.isLinux) {
    configDirectory = "/etc/ocsinventory-agent";
  } else if (Platform.isMacOS) {
    configDirectory = "/etc/ocsinventory-agent";
  } else if (Platform.isWindows) {
    configDirectory = "C:/ProgramData/OCSInventory-Agent";
  } else {
    stdout.writeln("Unsupported platform detected.");
    exit(1);
  }

  int logLevel = 2;
  if (allArgs.wasParsed("log_level")) {
    logLevel = int.parse(allArgs.option("log_level").toString());
    if (logLevel < 0 || logLevel > 3) {
      stdout.writeln("Log level must be between 0 and 3. Defaulted to 2.");
    }
  }

  int mode = 4;
  if (allArgs.wasParsed("mode")) {
    mode = int.parse(allArgs.option("mode").toString());
    if (mode < 0 || mode > 4) {
      stdout.writeln(
          "Mode must be between 0 and 4. Defaulted to 4 (Local without template).");
    }
  }

  bool logFile = false;
  if (allArgs.wasParsed("log_file")) {
    logFile = allArgs.option("log_file").toString() == "true";
    if (allArgs.option("log_file").toString() != "true" &&
        allArgs.option("log_file").toString() != "false") {
      stdout
          .writeln("Log file should be 'true' or 'false'. Defaulted to false.");
    }
  }

  int executionTimeout = 120;
  if (allArgs.wasParsed("execution_timeout")) {
    executionTimeout =
        int.tryParse(allArgs.option("execution_timeout").toString()) ?? 120;
    if (executionTimeout <= 0) {
      stdout.writeln(
          "Execution timeout must be a positive number of seconds. Defaulted to 120.");
      executionTimeout = 120;
    }
  }

  bool bypassCertificate = false;
  if (allArgs.wasParsed("bypass-certificate")) {
    bypassCertificate =
        allArgs.option("bypass-certificate").toString() == "true";
    if (allArgs.option("bypass-certificate").toString() != "true" &&
        allArgs.option("bypass-certificate").toString() != "false") {
      stdout.writeln(
          "Bypass certificate should be 'true' or 'false'. Defaulted to false.");
    }
  }

  Map<String, dynamic> inventoryConfigurations = {};
  inventoryConfigurations['log_file'] = logFile;
  inventoryConfigurations['mode'] = mode;
  inventoryConfigurations['password'] =
      await allArgs.option("password").toString();
  inventoryConfigurations['username'] =
      await allArgs.option("username").toString();
  inventoryConfigurations['url'] = await allArgs.option("url").toString();
  inventoryConfigurations['data_directory'] =
      await allArgs.option("data_directory").toString();
  inventoryConfigurations['log_file_path'] =
      await allArgs.option("log_file_path").toString();
  inventoryConfigurations['log_level'] = logLevel;
  inventoryConfigurations['certificate'] =
      await allArgs.option("certificate").toString();
  inventoryConfigurations["bypass-certificate"] = bypassCertificate;
  inventoryConfigurations['execution_timeout'] = executionTimeout;

  config = await Config(
      configDirectory, jsonEncode(inventoryConfigurations).toString());

  if (allArgs.wasParsed("certificate")) {
    File certificate = File(allArgs.option("certificate").toString());
    if (certificate.existsSync()) {
      // Copy the certificate to the config directory
      String certificatePath = configDirectory + "/cert.pem";
      if (Platform.isWindows) {
        certificatePath = configDirectory + "\\cert.pem";
      }

      certificate.copySync(certificatePath);
      inventoryConfigurations["certificate"] = certificatePath;
    }
  }

  inventoryConfigurations.forEach((key, value) {
    if (allArgs.wasParsed(key)) {
      // Update the content of the map into the config class
      config.setConfigFileContentByKey(key, value);
      // if --overwrite_config update the config file
      if (allArgs.wasParsed("overwrite_config") == true &&
          allArgs.option("overwrite_config").toString() == "true") {
        config.updateInventoryConfig(key, value);
        Config.readOnly = false;
      }
    }
  });

  // Initiate logger
  Logger logger = new Logger(config);

  // Initiate common
  FilesUtils filesUtils = new FilesUtils();
  HTTPUtils httpUtils = new HTTPUtils(logger, config);
  JsonUtils jsonUtils = new JsonUtils();

  // Initiate core
  Commands commands = new Commands(logger, config);
  BaseLinux baseLinux = new BaseLinux(logger, commands, filesUtils, jsonUtils);
  BaseMacOS baseMacOS = new BaseMacOS(logger, commands);
  BaseWindows baseWindows =
      new BaseWindows(logger, commands, filesUtils, jsonUtils);
  Format format = new Format(logger, commands);

  // Initiate modules
  Inventory inventory = new Inventory(
      logger, config, filesUtils, httpUtils, jsonUtils, commands, format);
  Deployment deployment = new Deployment(logger, config, httpUtils, commands);

  // Get the agent execution mode
  Map<int, String> enumMode = {
    0: "Installer mode",
    1: "Remote with template",
    2: "Remote without template",
    3: "Local with template",
    4: "Local without template",
  };

  if (await allArgs.option("service").toString() == "true") {
    try {
      new Daemon(config, logger);
    } catch (e) {
      logger.error("Service",
          "An error occurred while starting the daemon: ${e.toString()}");
    }
    return;
  }

  logger.info("APP",
      sprintf("Starting agent in %s mode...", [enumMode[inventory.getMode()]]));

  //Get the config execution mode
  if (Config.readOnly == true) {
    logger.info("Config",
        "Command-line arguments will override config values for this run only (no persistent change).");
  } else {
    logger.info("Config",
        "Command-line arguments will overwrite values in the config file (persistent change).");
  }
  // Get the OS body
  var body, os;
  if (Platform.isLinux) {
    body = await baseLinux.getBody();
    os = "LIN";
  } else if (Platform.isMacOS) {
    body = await baseMacOS.getBody();
    os = "MAC";
  } else if (Platform.isWindows) {
    body = await baseWindows.getBody();
    os = "WIN";
  } else {
    logger.error("APP", "The detected operating system is unsupported.");
  }

  if (inventory.getMode() == 0 ||
      inventory.getMode() == 1 ||
      inventory.getMode() == 2) {
    if (await inventory.checkApi()) {
      // Inventory process
      await inventory.checkInventoryExist(body);
      await inventory.checkAndApplyConfig();

      if (inventory.getMode() == 2 || inventory.getMode() == 1) {
        await inventory.sendRemoteBaseInventory(body);
        if (inventory.getMode() == 1) {
          await inventory.sendRemoteTemplateInventory(body);
        }
      }

      // Deployment process
      await deployment.processDeployment(os, inventory.assetID);
    }
  } else if (inventory.getMode() == 3 || inventory.getMode() == 4) {
    await inventory.sendLocalBaseInventory(body);
    if (inventory.getMode() == 3) {
      await inventory.sendLocalTemplateInventory();
    }
  }
  logger.info("APP", "Agent process completed successfully.");
}
