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
import 'dart:io';

// Common imports
import 'package:ocs_agent/core/common/files_utils.dart';
import 'package:ocs_agent/core/common/json_utils.dart';

/// Class to get config in config folder.
class Config {
  late FilesUtils filesUtils = new FilesUtils();
  late JsonUtils jsonUtils = new JsonUtils();

  final String coreFilename = "/core.json";
  final String inventoryFilename = "/inventory.json";
  final String templateFilename = "/template.json";

  late File inventory;
  late File core;
  late File template;

  static late String token = "";

  /// Constructor.
  Config(String configPath, String inventoryContent) {
    createInventoryConfigFile(configPath, inventoryContent);
  }

  /// Create inventory config file and set the content.
  void createInventoryConfigFile(
      String configPath, String inventoryContent) async {
    Directory configDir = Directory(configPath);
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    this.inventory = File(configPath + inventoryFilename);
    if (!this.inventory.existsSync()) {
      // Create the file and rite the default content to {}
      this.inventory.createSync(recursive: true);
      this.inventory.writeAsStringSync(inventoryContent);
    }
    await createOthersConfigFiles(configPath);
  }

  /// Create core and template config files.
  Future<void> createOthersConfigFiles(String configPath) async {
    this.core = File(configPath + coreFilename);
    if (!this.core.existsSync()) {
      // Create the file and rite the default content to []
      this.core.createSync(recursive: true);
      this.core.writeAsStringSync("[]");
    }

    this.template = File(configPath + templateFilename);
    if (!this.template.existsSync()) {
      // Create the file and rite the default content to {}
      this.template.createSync(recursive: true);
      this.template.writeAsStringSync("{}");
    }
  }

  /// Return all content in inventory config file.
  String getInventoryConfigs() {
    return this.jsonUtils.getContentFromFile(inventory).toString();
  }

  /// return [key] content in inventory file.
  dynamic getInventoryConfig(String key) {
    var returnValue = jsonUtils.getContentFromFileByKey(inventory, key);
    return returnValue;
  }

  /// Update inventory config file by [_index] and [_value].
  void updateInventoryConfig(String _index, dynamic _value) {
    String str = jsonUtils.setContentFromFile(inventory, _index, _value);
    if (!str.isEmpty) {
      filesUtils.rewriteFile(inventory, str);
    }
  }

  /// Return all content in core config file.
  List<dynamic> getCoreConfigs() {
    return jsonUtils.getContentFromFile(core);
  }

  /// return [key] content in core file.
  dynamic getCoreConfig(String module, String key) {
    dynamic result = false;
    getCoreConfigs().forEach((element) {
      if (element["name"] == module) {
        element["value"].forEach((value) {
          if (value["name"] == key) {
            result = value["value"];
          }
        });
      }
    });
    return result;
  }

  /// Update core config file by [_index] and [_value].
  void updateCoreConfig(String _index, String _value) {
    String str = jsonUtils.setContentFromFile(core, _index, _value);
    if (!str.isEmpty) {
      filesUtils.rewriteFile(core, str);
    }
  }

  /// Update all core file.
  void setCore(String strCore) {
    filesUtils.rewriteFile(core, strCore);
  }

  /// return template file in json format.
  Map<String, dynamic> getTemplate() {
    return jsonUtils.getContentFromFile(template);
  }

  /// return [key] content in template file.
  String getTemplateKey(String key) {
    return jsonUtils.getContentFromFileByKey(template, key);
  }

  /// Update core template file by [_index] and [_value].
  void updateTemplate(String _index, String _value) {
    String str = jsonUtils.setContentFromFile(template, _index, _value);
    if (!str.isEmpty) {
      filesUtils.rewriteFile(template, str);
    }
  }

  /// Update all template file.
  void setTemplate(String strTemplate) {
    filesUtils.rewriteFile(template, strTemplate);
  }
}
