import 'package:ocs_agent/core/inventory/linux/commands.dart' as command;

///This fonction return the body for to asset/bases
dynamic getBody() async {
  var linuxCommand = new command.LinuxCommand();

  dynamic interface =
      (await linuxCommand.commandShell("ip route show default", true))
          .split(" ")[4];

  dynamic body = ({
    "name": await linuxCommand.commandShell("uname -n", true),
    "description": await linuxCommand.commandShell("uname -m", true),
    "serial": await linuxCommand.commandShell(
        "sudo dmidecode -s system-serial-number", true),
    "osname": await linuxCommand.commandShell("uname -o", true),
    "osversion": await linuxCommand.commandShell("uname -v", true),
    "uuid":
        await linuxCommand.commandShell("sudo dmidecode -s system-uuid", true),
    "srcip":
        (await linuxCommand.commandShell("hostname -I", true)).split(" ")[0],
    "srcmac":
        await linuxCommand.readFile("/sys/class/net/$interface/address", true),
    "domain": await linuxCommand.commandShell("dnsdomainname", true)
  });

  return body;
}
