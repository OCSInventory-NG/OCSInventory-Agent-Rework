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
import 'package:ocs_agent/core/config.dart';

// Common imports
import 'package:ocs_agent/core/common/http_utils.dart';

/// Insert log in console or file if configured in inventory.json.
/// Level 0 = error
/// Level 1 = warning
/// Level 2 = info (default)
/// Level 3 = verbose
class Logger {
  late Config config;

  late bool _isFile;
  late String _url;
  late int _logLevel;

  late File file;

  late DateFormat dateFormat;

  /// Constructor.
  Logger(Config config) {
    this.config = config;

    _isFile = config.getInventoryConfig("log_file");
    _url = config.getInventoryConfig("url");
    _logLevel = config.getInventoryConfig("log_level");

    if (_isFile) {
      file = File(config.getInventoryConfig("log_file_path"));
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
    }

    dateFormat = DateFormat('EEE MMM dd HH:mm:ss yyyy');
  }

  /// Print error message only.
  void error(String className, String error) {
    if (_logLevel >= 0) {
      _logMessage("ERROR", className, error);
    }
  }

  /// Print error and warning messages.
  void warning(String className, String warning) {
    if (_logLevel >= 1) {
      _logMessage("WARNING", className, warning);
    }
  }

  /// Print info, warning, and error messages.
  void info(String className, String info) {
    if (_logLevel >= 2) {
      _logMessage("INFO", className, info);
    }
  }

  /// Print verbose message.
  void verbose(String className, String verbose) {
    if (_logLevel >= 3) {
      _logMessage("VERBOSE", className, verbose);
    }
  }

  /// Log message based on the specified level.
  void _logMessage(String level, String className, String message) {
    var now = DateTime.now();
    String date = dateFormat.format(now);
    String txt = "[$date] [$level] [$className] $message";
    if (_isFile) {
      file.writeAsStringSync(txt, mode: FileMode.append);
    } else {
      print(txt);
    }
  }

  /// Send formatted logs to the server
  void serverLogger(int assetID, int errorCode, String comment) async {
    if (assetID != -1) {
      HTTPUtils query = new HTTPUtils(this, config);
      Map<int, String> errorCodes = {
        0: "UNKNOWN",
        1: "INVENTORY_BASE_INSERT",
        2: "INVENTORY_BASE_UPDATE",
        3: "INVENTORY_EXT_INSERT",
        4: "INVENTORY_EXT_UPDATE",
        5: "INVENTORY_BASE_ERR",
        6: "INVENTORY_EXT_ERR",
        7: "DEPLOYMENT_ACK",
        8: "DEPLOYMENT_ERR",
        9: "CONFIG_UPDATE",
        10: "CONFIG_ERR",
        11: "TEMPLATE_UPDATE",
        12: "TEMPLATE_ERR"
      };
      String token = Config.token;
      Map<String, dynamic> content = new Map();
      content["asset"] = assetID;
      content["scope"] = errorCodes[errorCode];
      content["comment"] = comment;
      try {
        await query.post(
            Uri.parse("$_url/asset/logs/"),
            {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.authorizationHeader: "Token $token"
            },
            jsonEncode(content));
      } catch (exception) {
        error(this.runtimeType.toString(),
            sprintf("HTTP query: %s", [exception.toString().trim()]));
      }
    } else {
      error(this.runtimeType.toString(), "Failed to send remote logs!");
    }
  }
}
