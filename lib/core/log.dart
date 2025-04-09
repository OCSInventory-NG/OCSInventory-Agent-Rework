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
  late int _serverLogLevel;

  late File file;

  late DateFormat dateFormat;

  /// Constructor.
  Logger(Config config) {
    this.config = config;

    _isFile = config.getInventoryConfig("log_file");
    _url = config.getInventoryConfig("url");
    _logLevel = config.getInventoryConfig("log_level");
    String serverLogLevel = config.getCoreConfig("agent", "inventory_loglevel");
    _serverLogLevel = _stringToLevel(serverLogLevel);

    if (_isFile) {
      file = File(config.getInventoryConfig("log_file_path"));
      if (!file.existsSync()) {
        file.createSync(recursive: true);
      }
    }

    dateFormat = DateFormat('EEE MMM dd HH:mm:ss yyyy');
  }

  /// Print critical error message
  void critical(String className, String error) {
    if (_logLevel >= 0) {
      _logMessage("CRITICAL", className, error);
    }
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
    String txt = "[$date] [$level] [$className] $message\n";
    if (_isFile) {
      file.writeAsStringSync(txt, mode: FileMode.append);
    } else {
      print(txt);
    }
  }

  /// Send formatted logs to the server
  void serverLogger(int assetID, int errorCode, String comment) async {
    if (assetID == -1) {
      error(runtimeType.toString(),
          "Asset ID is not defined yet. Logging to server is not possible yet.");
      return;
    }

    // error code to log level and scope
    Map<int, dynamic> errorMapping = {
      0: {"level": 2, "scope": "UNKNOWN"}, // WARNING
      1: {"level": 3, "scope": "INVENTORY_BASE_INSERT"}, // DEBUG
      2: {"level": 3, "scope": "INVENTORY_BASE_UPDATE"}, // DEBUG
      3: {"level": 3, "scope": "INVENTORY_EXT_INSERT"}, // DEBUG
      4: {"level": 3, "scope": "INVENTORY_EXT_UPDATE"}, // DEBUG
      5: {"level": 1, "scope": "INVENTORY_BASE_ERR"}, // ERROR
      6: {"level": 1, "scope": "INVENTORY_EXT_ERR"}, // ERROR
      7: {"level": 3, "scope": "DEPLOYMENT_ACK"}, // DEBUG
      8: {"level": 1, "scope": "DEPLOYMENT_ERR"}, // ERROR
      9: {"level": 3, "scope": "CONFIG_UPDATE"}, // DEBUG
      10: {"level": 1, "scope": "CONFIG_ERR"}, // ERROR
      11: {"level": 4, "scope": "TEMPLATE_UPDATE"}, // DEBUG
      12: {"level": 1, "scope": "TEMPLATE_ERR"} // ERROR
    };

    var mapping = errorMapping[errorCode] ?? {"level": 2, "scope": "UNKNOWN"};
    int logLevel = mapping["level"];

    if (logLevel > _serverLogLevel) {
      return;
    }

    HTTPUtils query = HTTPUtils(this, config);
    String token = config.getInventoryConfig("token");
    Map<String, dynamic> content = {
      "asset": assetID,
      "scope": mapping["scope"],
      "comment": comment,
      "level": _levelToString(logLevel)
    };

    try {
      await query.post(
          Uri.parse("$_url/asset/logs/"),
          {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.authorizationHeader: "Token $token"
          },
          jsonEncode(content));
    } catch (exception) {
      error(runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
    }
  }

  // helper to convert numeric level to string
  String _levelToString(int level) {
    switch (level) {
      case 0:
        return "CRITICAL";
      case 1:
        return "ERROR";
      case 2:
        return "WARNING";
      case 3:
        return "INFO";
      case 4:
        return "DEBUG";
      default:
        return "WARNING";
    }
  }

  // helper to convert string level to numeric value
  int _stringToLevel(String level) {
    switch (level.toUpperCase()) {
      case "CRITICAL":
        return 0;
      case "ERROR":
        return 1;
      case "WARNING":
        return 2;
      case "INFO":
        return 3;
      case "DEBUG":
        return 4;
      default:
        // default to WARNING
        return 2;
    }
  }
}
