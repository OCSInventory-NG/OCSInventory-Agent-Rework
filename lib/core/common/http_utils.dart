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

// External packages imports
import 'dart:convert';
import 'dart:io';
import 'package:http/io_client.dart';
import 'package:ocs_agent/core/config.dart';
import 'package:sprintf/sprintf.dart';

// Core imports
import 'package:ocs_agent/core/log.dart';

/// This class will execute and log the status of the query
class HTTPUtils {
  late Logger logger;
  late IOClient ioClient;
  late Config config;

  /// Constructor
  HTTPUtils(Logger logger, Config config) {
    this.logger = logger;
    this.config = config;
    this.ioClient = createHttpsClient();
  }

  /// Return header in json format.
  Map<String, String> getHeader() {
    // Get data from inventory.json file
    String token = Config.token;

    return {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: "Token $token"
    };
  }

  /// Create https client
  IOClient createHttpsClient() {
    bool bypassCertificate = config.getInventoryConfig("bypass_certificate").toString() == "true";
    try {
      if (bypassCertificate) {
        SecurityContext context = SecurityContext(withTrustedRoots: false);
        String certificate = File(config.getInventoryConfig("certificate")).readAsStringSync();
        context.setTrustedCertificatesBytes(utf8.encode(certificate));
        
        HttpClient client = HttpClient(context: context)
          ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
        return IOClient(client);
      } else {
        return IOClient(HttpClient());
      }
    } catch (exception) {
      logger.error(this.runtimeType.toString(), sprintf("HTTP query: %s", [exception.toString().trim()]));
      return IOClient(HttpClient());
    }
  }

  /// Return the statusCode message
  String? statusCodeMessage(String type, int statusCode, String detail) {
    var statusMessage = new Map<int, String>();
    statusMessage[200] = sprintf("[%s] [200] %s", [type, detail]);
    statusMessage[201] = sprintf("[%s] [201] %s", [type, detail]);
    statusMessage[400] = sprintf("[%s] [400] %s", [type, detail]);
    statusMessage[401] = sprintf("[%s] [401] %s", [type, detail]);
    statusMessage[403] = sprintf("[%s] [403] %s", [type, detail]);
    statusMessage[404] = sprintf("[%s] [404] %s", [type, detail]);
    statusMessage[500] = sprintf("[%s] [500] %s", [type, detail]);
    return statusMessage[statusCode];
  }

  /// Do a delete HTTP query
  Future<Map<String, dynamic>> delete(
      Uri uri, Map<String, String>? headers) async {
    var returnObject = new Map<String, dynamic>();
    try {
      var query = await ioClient.delete(uri, headers: headers);
      returnObject["body"] = query.body;
      returnObject["status_code"] = query.statusCode;
      returnObject["message"] =
          statusCodeMessage("DELETE", query.statusCode, query.body);
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      returnObject["error"] = true;
    }
    return returnObject;
  }

  /// Do a get HTTP query
  Future<Map<String, dynamic>> get(
      Uri uri, Map<String, String>? headers) async {
    var returnObject = new Map<String, dynamic>();
    try {
      var query = await ioClient.get(uri, headers: headers);
      returnObject["body"] = query.body;
      returnObject["status_code"] = query.statusCode;
      returnObject["message"] =
          statusCodeMessage("GET", query.statusCode, query.body);
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      returnObject["error"] = true;
    }
    return returnObject;
  }

  /// Do a patch HTTP query
  Future<Map<String, dynamic>> patch(
      Uri uri, Map<String, String>? headers, Object? body) async {
    var returnObject = new Map<String, dynamic>();
    try {
      var query = await ioClient.patch(uri, headers: headers, body: body);
      returnObject["body"] = query.body;
      returnObject["status_code"] = query.statusCode;
      returnObject["message"] =
          statusCodeMessage("PATCH", query.statusCode, query.body);
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      returnObject["error"] = true;
    }
    return returnObject;
  }

  /// Do a post HTTP query
  Future<Map<String, dynamic>> post(
      Uri uri, Map<String, String>? headers, Object? body) async {
    var returnObject = new Map<String, dynamic>();
    try {
      var query = await ioClient.post(uri, headers: headers, body: body);
      returnObject["body"] = query.body;
      returnObject["status_code"] = query.statusCode;
      returnObject["message"] =
          statusCodeMessage("POST", query.statusCode, query.body);
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      returnObject["error"] = true;
    }
    return returnObject;
  }

  /// Do a put HTTP query
  Future<Map<String, dynamic>> put(
      Uri uri, Map<String, String>? headers, Object? body) async {
    var returnObject = new Map<String, dynamic>();
    try {
      var query = await ioClient.put(uri, headers: headers, body: body);
      returnObject["body"] = query.body;
      returnObject["status_code"] = query.statusCode;
      returnObject["message"] =
          statusCodeMessage("PUT", query.statusCode, query.body);
    } catch (exception) {
      logger.error(this.runtimeType.toString(),
          sprintf("HTTP query: %s", [exception.toString().trim()]));
      returnObject["error"] = true;
    }
    return returnObject;
  }
}
