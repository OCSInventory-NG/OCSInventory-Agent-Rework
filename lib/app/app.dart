import 'dart:io' show Platform;

import 'package:ocs_agent/core/api.dart' as api;

import 'package:ocs_agent/core/inventory/linux/baseLinux.dart' as baseLinux;

import 'package:ocs_agent/core/inventory/macos/baseMacOS.dart' as baseMacOS;

import 'package:ocs_agent/core/inventory/windows/baseWindows.dart'
    as baseWindows;

///in this main section we send the [body] to the asset/bases
void main(List<String> args) async {
  var sendBody = new api.Api();

  sendBody.generateToken();

  sendBody.apiCheck();

  sendBody.getHeader();

  sendBody.getTemplate(sendBody.getIdTemplate());

  if (Platform.isMacOS) {
    sendBody.sendInventory(await baseMacOS.getBody());
  } else if (Platform.isLinux) {
    sendBody.sendInventory(await baseLinux.getBody());
  } else if (Platform.isWindows) {
    sendBody.sendInventory(await baseWindows.getBody());
  } else {
    sendBody.logger.error("Error Platform");
  }

  sendBody.getInventory();
}
