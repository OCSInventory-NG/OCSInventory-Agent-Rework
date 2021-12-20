import 'package:ocs_agent/core/inventory/macos/commands.dart' as command;

///This fonction return the body for to asset/bases
dynamic getBody() async {
  var macOsCommand = new command.MacOSCommand();

  /// This command [commandSerialUUID] display list Serial and UUID
  String commandSerialUUID;
  commandSerialUUID = await macOsCommand.commandShell(
      "system_profiler SPHardwareDataType", true);

  /// Regex to get [Serial]
  RegExp regexpSerial;
  regexpSerial = RegExp(r"(?<=Serial\sNumber\s\(system\):\s)\w+");
  String getSerial;
  getSerial = regexpSerial.stringMatch(commandSerialUUID).trim();

  /// Regex to get [UUID]
  RegExp regexpUUID;
  regexpUUID = RegExp(r"(?<=Hardware\sUUID:\s)(\w*-\w*-\w*-\w*-\w*)?\n");
  String getUUID;
  getUUID = regexpUUID.stringMatch(commandSerialUUID).trim();

  /// Get default route, regExp to Interface for [srcip] and [srcmac]
  String getDefaultRoute;
  getDefaultRoute = await macOsCommand.commandShell("route get default", true);
  RegExp regexpInterface;
  regexpInterface = RegExp(r"(?<=interface:\s)\w*");
  String getInterface;
  getInterface = regexpInterface.stringMatch(getDefaultRoute);

  /// Get domains list and apply this Regex to get domain
  String listDomains;
  listDomains = await macOsCommand.commandShell("scutil --dns", true);
  RegExp regexpDomain;
  regexpDomain = RegExp(r'(?<=search\sdomain\[0\]\s:\s)\w*.[a-z]{0,4}');
  String getDomain;
  getDomain = regexpDomain.stringMatch(listDomains).trim();

  dynamic body = ({
    "name": await macOsCommand.commandShell("hostname", true),
    "description": await macOsCommand.commandShell("uname -m", true),
    "serial": getSerial,
    "osname": await macOsCommand.commandShell("sw_vers -productName", true),
    "osversion":
        await macOsCommand.commandShell("sw_vers -productVersion", true),
    "uuid": getUUID,
    "srcip": await macOsCommand.commandShell(
        "ipconfig getifaddr $getInterface", true),
    "srcmac": (await macOsCommand.commandShell(
            "networksetup -getmacaddress $getInterface", true))
        .split(" ")[2],
    "domain": getDomain
  });

  return body;
}
