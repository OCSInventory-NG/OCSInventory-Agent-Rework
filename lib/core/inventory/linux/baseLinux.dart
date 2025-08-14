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
import 'dart:math';
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocs_agent/core/log.dart';
import 'package:ocs_agent/core/inventory/commands.dart';

// Common imports
import 'package:ocs_agent/core/common/files_utils.dart';
import 'package:ocs_agent/core/common/json_utils.dart';
import 'package:ocs_agent/core/config.dart';

class BaseLinux {
  late Logger logger;
  late Config config;
  late Commands commands;
  FilesUtils filesUtils;
  JsonUtils jsonUtils;
  final String serialFileName = "/serialNumber.json";
  final String logType = "BaseInventory";

  /// Constructor
  BaseLinux(
      this.logger, this.config, this.commands, this.filesUtils, this.jsonUtils);

  ///This fonction return the body for to asset/bases
  dynamic getBody() async {
    logger.info(this.runtimeType.toString(), "Platform: LINUX");

    logger.info(this.runtimeType.toString(), "Retrieving OS body...");

    dynamic getOSRelease = (await commands.processTarget(
            "FILE", "/etc/os-release", logType, "OS VERSION"))["value"]
        .toString()
        .split("\n");
    Map<String, String> osRelease = {};
    for (final info in getOSRelease) {
      RegExp exp = RegExp(r'(?<key>[\S]+?)="(?<value>[\S\s]+?)"');
      RegExpMatch? match = exp.firstMatch(info);
      if (match != null) {
        final entry = <String, String>{
          match.namedGroup("key").toString():
              match.namedGroup("value").toString()
        };
        osRelease.addEntries(entry.entries);
      }
    }

    dynamic getHostnamectl = (await commands.processTarget(
            "BASH", "hostnamectl", logType, "DESCRIPTION"))["value"]
        .toString()
        .split("\n");
    Map<String, String> hostnamectl = {};
    for (final info in getHostnamectl) {
      RegExp exp = RegExp(r'(?<key>[^\n][\S\s]+?): (?<value>[\S\s][^\n]+)');
      RegExpMatch? match = exp.firstMatch(info);
      if (match != null) {
        final entry = <String, String>{
          match.namedGroup("key").toString().trim():
              match.namedGroup("value").toString()
        };
        hostnamectl.addEntries(entry.entries);
      }
    }

    dynamic interfaces = (await commands.processTarget(
            "BASH", "ip route show default", logType, "INTERFACES"))["value"]
        .toString()
        .split("\n");

    String macAddressList = "";

    for (final route in interfaces) {
      if (route.isNotEmpty) {
        final interface = route.split(" ")[4];
        final result = await commands.processTarget(
            "BASH", "ip link show $interface", logType, "MAC ADDRESS");
        final getMacAddress = result["value"].toString();

        final exp = RegExp(r'link\/ether (?<mac>[0-9a-fA-F:]{17})');
        final match = exp.firstMatch(getMacAddress);
        if (match != null) {
          final mac = match.namedGroup("mac")?.trim();
          if (mac != null && !macAddressList.contains(mac)) {
            macAddressList += '$mac ';
          }
        }
      }
    }

    String? macAddress = macAddressList.split(' ')[0];

    if (macAddress == "") {
      logger.warning(
          this.runtimeType.toString(), "No valid MAC address found.");
      return null;
    }

    // Get name
    String name = (await commands.processTarget(
            "BASH", "hostname", logType, "NAME"))["value"]
        .toString()
        .trim();

    dynamic body = ({
      "name": name,
      "description": osRelease["PRETTY_NAME"].toString() +
          " " +
          hostnamectl["Architecture"].toString(),
      "serial": await _getSerialNumber(name, macAddress),
      "osname": osRelease["NAME"].toString(),
      "osversion": osRelease["VERSION_ID"].toString(),
      "uuid": await _getUUID(name, macAddress),
      "srcip": (await commands.processTarget(
              "BASH", "hostname -I", logType, "IP ADDRESS"))["value"]
          .toString()
          .split(" ")[0],
      "srcmac": macAddressList,
      "domain": (await commands.processTarget(
          "BASH", "hostname -d", logType, "DOMAIN"))["value"],
      "agent": Config.agentVersion,
      "template": config.getTemplateKey("id"),
    });

    logger.info(this.runtimeType.toString(), "OS body retrieved successfully.");

    return body;
  }

  /// Get UUID or generate one if not available and save it in a uuid file
  Future<String> _getUUID(String name, String macAddress) async {
    String uuid = (await commands.processTarget(
            "BASH", "dmidecode -s system-uuid", logType, "UUID"))["value"]
        .toString();

    if (uuid == "") {
      String containerFileName = sprintf('%s.json', ["generated_uuid"]);
      File containerLinuxFile = File(containerFileName);
      if (!containerLinuxFile.existsSync()) {
        containerLinuxFile.createSync(recursive: true);
        containerLinuxFile.writeAsStringSync("{}");
      }
      Map<String, dynamic> containerLinux =
          jsonUtils.getContentFromFile(containerLinuxFile);

      if (containerLinux.isNotEmpty &&
          containerLinux.containsValue(name) &&
          containerLinux.containsValue(macAddress)) {
        uuid = containerLinux["uuid"];
        logger.info(this.runtimeType.toString(), "UUID file found.");
      } else {
        logger.info(
            this.runtimeType.toString(), "No system UUID, generating new one.");
        uuid = (await commands.processTarget(
                "BASH", "uuidgen", logType, "UUID"))["value"]
            .toString();
        dynamic baseAdded = {};
        baseAdded["name"] = name;
        baseAdded["uuid"] = uuid;
        baseAdded["MAC"] = macAddress;

        JsonEncoder encoder = new JsonEncoder.withIndent('  ');
        String str = encoder.convert(baseAdded);
        FilesUtils filesUtils = new FilesUtils();
        filesUtils.rewriteFile(containerLinuxFile, str);
        logger.info(this.runtimeType.toString(), "New UUID saved to file.");
      }
    }
    return uuid;
  }

  Future<String> _getSerialNumber(String name, String macAddress) async {
    String serialResult = (await commands.processTarget(
            "BASH",
            "dmidecode -s system-serial-number",
            logType,
            "SERIAL NUMBER"))["value"]
        .toString();

    String path = "/etc/ocsinventory-agent" + serialFileName;

    File fileSn = File(path);

    bool existFile = await fileSn.exists();

    if (serialResult == "") {
      logger.info(this.runtimeType.toString(),
          "No system serial number from dmidecode, checking serial number file...");
      if (!existFile) {
        logger.info(this.runtimeType.toString(),
            "Serial number file not found, generating new serial number.");
        String generatedSerial = "OCS-GEN-" +
            macAddress.split(':').last +
            _randNumbers() +
            macAddress.split(':').first;
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
