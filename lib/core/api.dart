import 'dart:convert';
import 'dart:io';
import 'dart:io' show Platform;

import 'package:ocs_agent/core/log.dart';

import 'config.dart';
import 'inventory/linux/commands.dart';
import 'inventory/linux/format.dart';
import 'inventory/macos/commands.dart';
import 'inventory/macos/format.dart';
import 'inventory/windows/commands.dart';
import 'inventory/windows/format.dart';
import 'json_utils.dart';

import 'package:http/http.dart' as http;

/// This class communicate with the server.
class Api {
  Config config;
  JsonUtils jsonUtils;
  Logger logger;

  LinuxFormat linuxFormat;
  LinuxCommand linuxCommand;

  WindowsFormat windowsFormat;
  WindowsCommand windowsCommand;

  MacOSFormat macosFormat;
  MacOSCommand macosCommand;

  var url;

  /// Constructor.
  Api() {
    this.config = new Config();
    this.jsonUtils = new JsonUtils();
    this.linuxFormat = new LinuxFormat();
    this.linuxCommand = new LinuxCommand();
    this.windowsFormat = new WindowsFormat();
    this.windowsCommand = new WindowsCommand();
    this.macosFormat = new MacOSFormat();
    this.macosCommand = new MacOSCommand();
    this.logger = new Logger();
    this.url = config.getInventoryConfig("url");
  }

  /// Send to Api the username and password and
  /// save it in inventory.json.
  void generateToken() async {
    String username = config.getInventoryConfig("username");
    String password = config.getInventoryConfig("password");

    var response = await http.post(Uri.parse(this.url + "/api-auth/token"),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        body: jsonEncode({'username': username, 'password': password}));

    if (response.statusCode == 200) {
      config.updateInventoryConfig(
          "token", jsonUtils.getContentFromStringByKey(response.body, "token"));
    }
  }

  /// Check if api is working and generate token if not.
  void apiCheck() async {
    var url = Uri.parse(this.url);

    var response = await http.get(url, headers: this.getHeader());

    if (response.statusCode != 200) {
      this.generateToken();
    }
  }

  /// Send [body] to api /asset/bases.
  void sendInventory(Map<String, dynamic> body) async {
    /// Get the UUID of the body
    String uuid = await body['uuid'];

    var urlGet = Uri.parse(this.url + "/asset/bases/?uuid=$uuid");

    /// Get the inventory of this [uuid] in asset bases
    var responseGet = await http.get(urlGet, headers: this.getHeader());

    if (responseGet.statusCode == 200) {
      /// test if the body exist in asset bases or not
      if (responseGet.body.contains(uuid)) {
        /// Get the ID
        var getID = jsonDecode(responseGet.body);
        var id = getID[0]['id'];
        var urlUpdate = Uri.parse(this.url + "/asset/bases/$id/");
        var responseUpdate = await http.put(urlUpdate,
            headers: this.getHeader(), body: jsonEncode(body));
        if (responseUpdate.statusCode != 200) {
          logger.error("Error to update body");
        } else {
          logger.info("Inventory updating");
        }
      } else {
        var urlPost = Uri.parse(this.url + "/asset/bases/");
        var responsePost = await http.post(urlPost,
            headers: this.getHeader(), body: jsonEncode(body));

        if (responsePost.statusCode != 200) {
          logger.error("Error to send body");
        } else {
          logger.info("Inventory sending");
        }
      }
    }
  }

  /// return header in json format.
  Map<String, String> getHeader() {
    String token = config.getInventoryConfig("token");

    return {
      HttpHeaders.contentTypeHeader: 'application/json',
      HttpHeaders.authorizationHeader: "Token $token"
    };
  }

  /// Get and generate template with his [id].
  void getTemplate(id) async {
    var urlTemplates = Uri.parse(this.url + "/templates/$id/");
    var urlSections = Uri.parse(this.url + "/sections/");
    var urlFields = Uri.parse(this.url + "/fields/");

    var responseTemplates =
        await http.get(urlTemplates, headers: this.getHeader());
    var responseSections =
        await http.get(urlSections, headers: this.getHeader());
    var responseFields = await http.get(urlFields, headers: this.getHeader());

    if (responseTemplates.statusCode == 200 &&
        responseSections.statusCode == 200 &&
        responseFields.statusCode == 200) {
      Map<String, dynamic> template = json.decode(responseTemplates.body);
      List<dynamic> sections = json.decode(responseSections.body);
      List<dynamic> fields = json.decode(responseFields.body);

      sections.forEach((v) {
        var listfield = fields.where((map) => map['section'] == v['id']);
        v["fields"] = listfield.toList();
      });

      template["sections"] =
          sections.where((sec) => sec['template'] == id).toList();
      var encoder = new JsonEncoder.withIndent("\t");
      config.setTemplate(encoder.convert(template));
    }
  }

  /// Check if the template is not empty, get all informations from template
  /// and send inventory.
  getInventory() async {
    Map<String, dynamic> template = config.getTemplate();

    if (template == null) {
      logger.error("Template is empty");
    } else {
      var value = await this.getInventoryResult(template, template["os"]);
      logger.info("inventory 2 : $value");
      this.sendInventory(value);
    }
  }

  /// Get all informations present in the [template] from the computer
  /// with a [os] verification and format it in json.
  Future<Map<String, dynamic>> getInventoryResult(
      Map<String, dynamic> template, String os) async {
    var format;

    if (os == "LIN") {
      format = this.linuxFormat;
    } else if (template["os"] == "WIN" && Platform.isWindows) {
      format = this.windowsFormat;
    } else if (template["os"] == "MAC" && Platform.isMacOS) {
      format = this.macosFormat;
    } else {
      logger.error("Error to get the result");
    }

    Map<String, dynamic> inventory = new Map();

    List<dynamic> sections = template['sections'];

    for (var section in sections) {
      List<dynamic> fields = section['fields'];

      for (var field in fields) {
        String valueTarget;
        switch (section['retrival_output']) {
          case "TBLE":
            valueTarget = await format.getbyArray(section["target"],
                field["retrival_value"], section['retrival_method']);
            break;
          case "JSON":
            valueTarget = await format.getbyJson(section["target"],
                field["retrival_value"], section['retrival_method']);
            break;
          case "PTXT":
            valueTarget = await format.getbyPtxt(section["target"],
                field["retrival_value"], section['retrival_method']);
            break;
          default:
            valueTarget = null;
            break;
        }
        inventory.putIfAbsent(field['name'], () => valueTarget);
      }
    }

    return inventory;
  }
}
