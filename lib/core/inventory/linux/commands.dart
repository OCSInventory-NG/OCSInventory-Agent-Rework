import 'dart:io';

/// Class for execute command on linux.
class LinuxCommand {
  /// Execute [commandLine] to Shell.
  Future<String> commandShell(String commandLine) async {
    List<String> args = commandLine.split(" ");
    String command = args[0];
    args.removeAt(0);
    if (args == null) {
      args = [];
    }

    var process;
    await Process.run(command, args).then((value) => process = value.stdout);

    return process;
  }

  /// Return [path] file content.
  Future<String> readFile(String path) async {
    var process;
    await Process.run("cat", [path]).then((value) => process = value.stdout);

    return process;
  }

  /// Execute or read [command] in terms of [type].
  Future<String> getResult(String command, String type) async {
    switch (type) {
      case "FILE":
        return await this.readFile(command);
        break;
      case "CMD":
        return await this.commandShell(command);
        break;
      case "BASH":
        return await this.commandShell(command);
        break;
    }
  }
}
