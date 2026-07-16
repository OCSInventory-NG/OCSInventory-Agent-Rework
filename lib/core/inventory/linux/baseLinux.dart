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

class BaseLinux {
  late Logger logger;
  late Commands commands;
  FilesUtils filesUtils;
  JsonUtils jsonUtils;
  final String configDir = "/etc/ocsinventory-agent";
  final String serialFileName = "/serialNumber.json";
  final String uuidFileName = "/uuid.json";
  final String logType = "BaseInventory";

  /// Constructor
  BaseLinux(this.logger, this.commands, this.filesUtils, this.jsonUtils);

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

    List<String> macAddresses = [];

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
          if (mac != null && !macAddresses.contains(mac)) {
            macAddresses.add(mac);
          }
        }
      }
    }

    String macAddressList = macAddresses.join(',');
    String? macAddress = macAddresses.isNotEmpty ? macAddresses.first : null;

    if (macAddress == null || macAddress.isEmpty) {
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
      "uuid": await _getUUID(),
      "srcip": (await commands.processTarget(
              "BASH", "hostname -I", logType, "IP ADDRESS"))["value"]
          .toString()
          .split(" ")[0],
      "srcmac": macAddressList,
      "domain": (await commands.processTarget(
          "BASH", "hostname -d", logType, "DOMAIN"))["value"],
      "agent": Config.agentVersion,
    });

    logger.info(this.runtimeType.toString(), "OS body retrieved successfully.");

    return body;
  }

  /// Check if a command exists on the system
  Future<bool> _commandExists(String cmd) async {
    final result = await commands.processTarget(
      "BASH", "which $cmd", logType, "CHECK COMMAND",
    );
    return result["value"] != null && result["value"].toString().isNotEmpty;
  }

  /// Detects whether the process is running inside a container (LXC, Docker,
  /// Podman, systemd-nspawn, ...).
  ///
  /// In a container (especially unprivileged LXC), dmidecode exposes the
  /// host node's DMI table rather than its own independent one. This means
  /// every container hosted on the same physical host gets the same System
  /// UUID and the same serial number from dmidecode, causing device
  /// identification collisions on the OCS Inventory server (one container
  /// overwrites another container's inventory). dmidecode must therefore
  /// be avoided in this context, letting the agent fall back to the
  /// existing alternative mechanisms (local uuid/serial files, uuidgen, or
  /// random generation), which are correctly unique per container.
  Future<bool> _isContainerEnvironment() async {
    if (await _commandExists("systemd-detect-virt")) {
      final result = await commands.processTarget(
          "BASH", "systemd-detect-virt --container -q", logType, "VIRT CHECK");
      if (result["status"] == true) {
        return true;
      }
    }

    try {
      final containerFile = File('/run/systemd/container');
      if (await containerFile.exists()) {
        final content = (await containerFile.readAsString()).trim();
        if (content.isNotEmpty) {
          return true;
        }
      }
    } catch (_) {
      // Ignore and try the next method
    }

    try {
      final envFile = File('/proc/1/environ');
      if (await envFile.exists()) {
        final content = await envFile.readAsString();
        if (content.contains('container=')) {
          return true;
        }
      }
    } catch (_) {
      // Ignore: if we can't determine it, assume it's not a container
    }

    return false;
  }

  /// Generate a UUID if not available
  String _generateUUID() {
    final random = Random.secure();
    String hex(int length) =>
        List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }

  /// Get UUID or generate one if not available and save it in a uuid file
  Future<String> _getUUID() async {
    String uuid = "";
    bool isContainer = await _isContainerEnvironment();

    if (isContainer) {
      logger.info(this.runtimeType.toString(),
          "Container environment detected, skipping dmidecode system UUID (would collide with host/other containers on the same node).");
    } else if (await _commandExists("dmidecode")) {
      uuid = (await commands.processTarget(
        "BASH", "dmidecode -s system-uuid", logType, "UUID"))["value"]
        .toString();
    } else {
      logger.info(this.runtimeType.toString(),
          "dmidecode command not found, skipping system UUID.");
    }

    String uuidFilePath = configDir + uuidFileName;
    File uuidFile = File(uuidFilePath);
    bool uuidFileExists = await uuidFile.exists();

    if (uuid == "") {
      logger.info(this.runtimeType.toString(),
          "No system UUID from dmidecode, checking UUID file...");

      if (!uuidFileExists) {
        logger.info(this.runtimeType.toString(),
            "UUID file not found, generating new one.");
        if (await _commandExists("uuidgen")) {
          uuid = (await commands.processTarget(
                "BASH", "uuidgen", logType, "UUID"))["value"]
            .toString();
        filesUtils.writeFile(uuidFile, '{ "uuid": "$uuid" }');
        logger.info(this.runtimeType.toString(), "New UUID saved to file.");
        } else {
          logger.warning(this.runtimeType.toString(),
              "uuidgen command not found, cannot generate UUID.");
        }
      } else {
        Map<String, dynamic> uuidData = jsonUtils.getContentFromFile(uuidFile);
        if (uuidData.containsKey("uuid")) {
          uuid = uuidData["uuid"];
          logger.info(this.runtimeType.toString(), "UUID file found.");
        }
      }
    }
    if (uuid == "") {
        logger.warning(this.runtimeType.toString(),
            "No UUID available from file, dmidecode or uuidgen. Generating a random UUID.");
        uuid = _generateUUID();
        filesUtils.writeFile(uuidFile, '{ "uuid": "$uuid" }');
    }
    return uuid;
  }

  Future<String> _getSerialNumber(String name, String macAddress) async {
    String serialResult = "";
    bool isContainer = await _isContainerEnvironment();

    if (isContainer) {
      logger.info(this.runtimeType.toString(),
          "Container environment detected, skipping dmidecode serial number (would collide with host/other containers on the same node).");
    } else if (await _commandExists("dmidecode")) {
      serialResult = (await commands.processTarget(
              "BASH",
              "dmidecode -s system-serial-number",
              logType,
              "SERIAL NUMBER"))["value"]
          .toString();
    } else {
      logger.info(this.runtimeType.toString(),
          "dmidecode command not found, skipping system serial number.");
    }

    String path = configDir + serialFileName;

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
