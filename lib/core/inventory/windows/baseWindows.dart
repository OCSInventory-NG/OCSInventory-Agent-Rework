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
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocs_agent/core/log.dart';
import 'package:ocs_agent/core/inventory/commands.dart';

// Common imports
import 'package:ocs_agent/core/common/files_utils.dart';
import 'package:ocs_agent/core/common/json_utils.dart';
import 'package:ocs_agent/core/config.dart';

class BaseWindows {
  late Logger logger;
  late Config config;
  late Commands commands;
  late FilesUtils filesUtils;
  late JsonUtils jsonUtils;
  final String logType = "BaseInventory";

  /// Constructor
  BaseWindows(
      this.logger, this.config, this.commands, this.filesUtils, this.jsonUtils);

  ///This fonction return the body for the asset/bases
  dynamic getBody() async {
    logger.info(this.runtimeType.toString(), "Platform: WINDOWS");

    logger.info(this.runtimeType.toString(), "Retrieving OS body...");

    /// Command get the mac address list
    dynamic macAddr;
    macAddr = (await commands.processTarget(
        "CMD", "getmac", logType, "MAC ADDRESS"))["value"];

    /// RegExp to match mac address
    RegExp regexMacAddr;
    regexMacAddr = RegExp(r"([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})");

    /// Get the Mac Address value
    var getMacAddr;
    getMacAddr = regexMacAddr.stringMatch(macAddr)!.trim();

    /// Command get to get the IP
    String ip;
    ip = (await commands.processTarget(
            "CMD", "ipconfig", logType, "IP"))["value"]
        .toString();

    /// RegExp to match IP
    RegExp regexIP;
    regexIP = RegExp(r"((?:[0-9]{1,3}\.){3}[0-9]{1,3})");

    /// Get IP value
    var getIP;
    getIP = regexIP.stringMatch(ip)!.trim();

    // Get the name of the computer
    String name = (await commands.processTarget(
            "CMD", "hostname", logType, "NAME"))["value"]
        .toString();

    dynamic body = ({
      "name": name,
      "description": (await commands.processTarget(
              "PW",
              "(Get-WMIObject -Class Win32_ComputerSystemProduct).Description",
              logType,
              "DESCRIPTION"))["value"]
          .toString(),
      "serial": (await commands.processTarget(
              "PW",
              "(Get-WMIObject win32_Bios).SerialNumber",
              logType,
              "SERIAL NUMBER"))["value"]
          .toString(),
      "osname": (await commands.processTarget(
              "PW",
              "(Get-WMIObject win32_operatingsystem).name",
              logType,
              "OS NAME"))["value"]
          .toString()
          .split("|")[0],
      "osversion": (await commands.processTarget(
              "PW",
              "(Get-WMIObject win32_operatingsystem).Version",
              logType,
              "OS VERSION"))["value"]
          .toString(),
      "uuid": await _getUUID(name, getMacAddr),
      "srcip": await getIP,
      "srcmac": (await commands.processTarget(
              "PW",
              "Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | Select-Object -ExpandProperty MacAddress",
              logType,
              "MAC ADDRESS"))["value"]
          .toString(),
      "domain": (await commands.processTarget(
              "PW",
              "(Get-WMIObject -Class Win32_ComputerSystem).Domain",
              logType,
              "DOMAIN"))["value"]
          .toString(),
      "agent": Config.agentVersion,
      "template": config.getTemplateKey("id"),
    });

    logger.info(this.runtimeType.toString(), "OS body has been retrieved!");

    return body;
  }

  /// Get UUID or generate one if not available and save it in a uuid file
  Future<String> _getUUID(String name, String macAdress) async {
    String uuid = (await commands.processTarget(
            "PW",
            "(Get-WMIObject -Class Win32_ComputerSystemProduct).UUID",
            logType,
            "UUID"))["value"]
        .toString();

    if (uuid == "") {
      logger.info(this.runtimeType.toString(),
          "UUID not found, generating a new one...");
      uuid = (await commands.processTarget(
              "PW", "[guid]::NewGuid().ToString()", logType, "UUID"))["value"]
          .toString();
      String containerFileName = sprintf('%s.json', ["generated_uuid"]);
      File containerWindowsFile = File(containerFileName);
      if (!containerWindowsFile.existsSync()) {
        containerWindowsFile.createSync(recursive: true);
        containerWindowsFile.writeAsStringSync("{}");
      }
      Map<String, dynamic> containerWindows =
          jsonUtils.getContentFromFile(containerWindowsFile);

      if (containerWindows.isNotEmpty &&
          containerWindows.containsValue(name) &&
          containerWindows.containsValue(macAdress)) {
        uuid = containerWindows["uuid"];
        logger.info(this.runtimeType.toString(),
            "UUID has been retrieved from the uuid file.");
      } else {
        dynamic baseAdded = {};
        baseAdded["name"] = name;
        baseAdded["uuid"] = uuid;
        baseAdded["MAC"] = macAdress;

        JsonEncoder encoder = new JsonEncoder.withIndent('  ');
        String str = encoder.convert(baseAdded);
        filesUtils.rewriteFile(containerWindowsFile, str);
        logger.info(this.runtimeType.toString(),
            "UUID has been generated and saved in the uuid file.");
      }
    }
    return uuid;
  }
}
