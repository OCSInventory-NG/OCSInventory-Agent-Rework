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

import 'package:ocs_agent/core/common/files_utils.dart';
import 'package:ocs_agent/core/common/json_utils.dart';
import 'package:ocs_agent/core/log.dart';

import 'package:ocs_agent/core/inventory/windows/commands.dart' as command;
import 'package:sprintf/sprintf.dart';

///This fonction return the body for the asset/bases
dynamic getBody() async {
  var windowsCommand = new command.WindowsCommand();
  var logger = new Logger();

  logger.info("Plateform: WINDOWS");

  logger.info("Getting OS body...");

  /// Command get the mac address list
  dynamic macAddr;
  macAddr = await windowsCommand.commandCmd("getmac", true);

  /// RegExp to match mac address
  RegExp regexMacAddr;
  regexMacAddr = RegExp(r"([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})");

  /// Get the Mac Address value
  var getMacAddr;
  getMacAddr = regexMacAddr.stringMatch(macAddr)!.trim();

  /// Command get to get the IP
  String ip;
  ip = await windowsCommand.commandCmd("ipconfig", true);

  /// RegExp to match IP
  RegExp regexIP;
  regexIP = RegExp(r"((?:[0-9]{1,3}\.){3}[0-9]{1,3})");

  /// Get IP value
  var getIP;
  getIP = regexIP.stringMatch(ip)!.trim();

  // Get the name of the computer
  String name = await windowsCommand.commandCmd("hostname", true);

  dynamic body = ({
    "name": name,
    "description": await windowsCommand.commandPowershell(
        "(Get-WMIObject -Class Win32_ComputerSystemProduct).Description", true),
    "serial": await windowsCommand.commandPowershell(
        "(Get-WMIObject win32_operatingsystem).SerialNumber", true),
    "osname": (await windowsCommand.commandPowershell(
            "(Get-WMIObject win32_operatingsystem).name", true))
        .split("|")[0],
    "osversion": await windowsCommand.commandPowershell(
        "(Get-WMIObject win32_operatingsystem).Version", true),
    "uuid": await _getUUID(name, getMacAddr),
    "srcip": await getIP,
    "srcmac": await getMacAddr,
    "domain": await windowsCommand.commandPowershell(
        "(Get-WMIObject -Class Win32_ComputerSystem).Domain", true),
  });

  logger.info("OS body has been retrieved!");

  return body;
}

/// Get UUID or generate one if not available and save it in a uuid file
Future<String> _getUUID(String name, String macAdress) async {
  var windowsCommand = new command.WindowsCommand();
  JsonUtils jsonUtils = new JsonUtils();
  Logger logger = new Logger();
  String uuid = await windowsCommand.commandPowershell(
      "(Get-WMIObject -Class Win32_ComputerSystemProduct).UUID", true);

  if (uuid == "") {
    logger.info("UUID not found, generating a new one...");
    uuid = await windowsCommand.commandPowershell(
        "[guid]::NewGuid().ToString()", true);
    String containerFileName = sprintf('%s/%s.json', ["config/", "uuid"]);
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
      logger.info("UUID has been retrieved from the uuid file.");
    } else {
      dynamic baseAdded = {};
      baseAdded["name"] = name;
      baseAdded["uuid"] = uuid;
      baseAdded["MAC"] = macAdress;

      JsonEncoder encoder = new JsonEncoder.withIndent('  ');
      String str = encoder.convert(baseAdded);
      FilesUtils filesUtils = new FilesUtils();
      filesUtils.rewriteFile(containerWindowsFile, str);
      logger.info("UUID has been generated and saved in the uuid file.");
    }
  }
  return uuid;
}
