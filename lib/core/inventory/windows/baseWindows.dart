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
import 'dart:io';
import 'dart:math';
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocsinventory_agent/core/log.dart';
import 'package:ocsinventory_agent/core/inventory/commands.dart';

// Common imports
import 'package:ocsinventory_agent/core/common/files_utils.dart';
import 'package:ocsinventory_agent/core/common/json_utils.dart';
import 'package:ocsinventory_agent/core/config.dart';

class BaseWindows {
  late Logger logger;
  late Commands commands;
  late FilesUtils filesUtils;
  late JsonUtils jsonUtils;
  final String uuidFileName = "uuid.json";
  final String serialFileName = "serialNumber.json";
  final String configDirectory = "C:\\ProgramData\\OCSInventory-Agent";
  final String logType = "BaseInventory";

  /// Constructor
  BaseWindows(this.logger, this.commands, this.filesUtils, this.jsonUtils);

  ///This fonction return the body for the asset/bases
  dynamic getBody() async {
    logger.info(this.runtimeType.toString(), "Platform: WINDOWS");

    logger.info(this.runtimeType.toString(), "Retrieving OS body...");

    String macAddressesResult = (await commands.processTarget(
            "PW",
            "Get-NetAdapter | Where-Object {\$_.Status -eq 'Up'} | Select-Object -ExpandProperty MacAddress",
            logType,
            "MAC ADDRESS"))["value"]
        .toString();

    List<String> macAddresses = [];
    if (macAddressesResult.isNotEmpty) {
      List<String> rawMacs = macAddressesResult.trim().split('\n');
      for (String mac in rawMacs) {
        String trimmedMac = mac.trim();
        if (trimmedMac.isNotEmpty && !macAddresses.contains(trimmedMac)) {
          macAddresses.add(trimmedMac);
        }
      }
    }

    String macAddressList = macAddresses.join(',');
    String macAddress = macAddresses.isNotEmpty ? macAddresses.first : "";

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
      "serial": await _getSerialNumber(name, macAddress),
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
      "uuid": await _getUUID(),
      "srcip": await getIP,
      "srcmac": macAddressList,
      "domain": (await commands.processTarget(
              "PW",
              "(Get-WMIObject -Class Win32_ComputerSystem).Domain",
              logType,
              "DOMAIN"))["value"]
          .toString(),
      "agent": Config.agentVersion,
    });

    logger.info(this.runtimeType.toString(), "OS body has been retrieved!");

    return body;
  }

  /// Get UUID or generate one if not available and save it in a uuid file
  Future<String> _getUUID() async {
    // Check if uuid file exists
    String uuidFilePath = '$configDirectory\\$uuidFileName';
    File uuidFile = File(uuidFilePath);
    bool uuidFileExists = await uuidFile.exists();

    // 1: if file exists it's our uuid source
    if (uuidFileExists) {
      logger.info(this.runtimeType.toString(), "UUID file found, reading from file...");
      try {
        Map<String, dynamic> uuidData = jsonUtils.getContentFromFile(uuidFile);
        if (uuidData.containsKey("uuid") && uuidData["uuid"].toString().isNotEmpty) {
          logger.info(this.runtimeType.toString(), "UUID retrieved from file.");
          return uuidData["uuid"]; 
        }
      } catch (e) {
        logger.info(this.runtimeType.toString(), "Error reading UUID file, proceeding to WMI...");
      }
    }

    // 2: if file doesn't exixt get from dmi
    logger.info(this.runtimeType.toString(), "No valid UUID file, querying system WMI...");
    String uuid = (await commands.processTarget(
            "PW",
            "(Get-WMIObject -Class Win32_ComputerSystemProduct).UUID",
            logType,
            "UUID"))["value"]
        .toString().trim(); // .trim() per evitare spazi vuoti fastidiosi

    if (uuid == "") {
      logger.info(this.runtimeType.toString(), "No system UUID from WMI, generating new one...");
      uuid = (await commands.processTarget(
              "PW", "[guid]::NewGuid().ToString()", logType, "UUID"))["value"]
          .toString().trim();
          
      filesUtils.writeFile(uuidFile, '{ "uuid": "$uuid" }');
      logger.info(this.runtimeType.toString(), "New UUID generated and saved to file.");
    } else {
      logger.info(this.runtimeType.toString(), "UUID successfully retrieved from WMI.");
    }

    return uuid;
  }

  Future<String> _getSerialNumber(String name, String macAddress) async {
    String serialResult = (await commands.processTarget(
            "PW",
            "(Get-WMIObject win32_Bios).SerialNumber",
            logType,
            "SERIAL NUMBER"))["value"]
        .toString();

    String path = '$configDirectory\\$serialFileName';

    File fileSn = File(path);

    bool existFile = await fileSn.exists();

    if (serialResult == "") {
      logger.info(this.runtimeType.toString(),
          "No system serial number from WMI, checking serial number file...");
      if (!existFile) {
        logger.info(this.runtimeType.toString(),
            "Serial number file not found, generating new serial number.");
        String cleanMac = macAddress.replaceAll('-', ':');
        String generatedSerial = "OCS-GEN-" +
            cleanMac.split(':').last +
            _randNumbers() +
            cleanMac.split(':').first;
        filesUtils.writeFile(fileSn, '{ "serial": "$generatedSerial" }');
        serialResult = generatedSerial;
      } else {
        Map<String, dynamic> serialData = jsonUtils.getContentFromFile(fileSn);
        serialResult = serialData["serial"];
        logger.info(this.runtimeType.toString(), "Serial number file found.");
      }
    }
    return serialResult;
  }

  String _randNumbers() {
    String result = "";

    for (int i = 0; i < 10; i++) {
      result += Random().nextInt(10).toString();
    }
    return result;
  }
}
