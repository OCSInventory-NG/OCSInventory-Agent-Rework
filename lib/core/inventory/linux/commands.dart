import 'dart:io';

/// Class for execute command on linux.
class LinuxCommand {
  /// Execute [commandLine] to Shell.
  Future<String> commandShell(String commandLine, bool normalization) async {
    List<String> args = commandLine.split(" ");
    String command = args[0];
    args.removeAt(0);
    if (args == null) {
      args = [];
    }

    var process;
    if (normalization) {
      String processNormalization;
      await Process.run(command, args)
          .then((value) => processNormalization = value.stdout);
      process = processNormalization.trim();
    } else {
      await Process.run(command, args).then((value) => process = value.stdout);
    }

    return process;
  }

  /// Return [path] file content.
  Future<String> readFile(String path, bool normalization) async {
    var process;
    if (normalization) {
      String processNormalization;
      await Process.run("cat", [path])
          .then((value) => processNormalization = value.stdout);
      process = processNormalization.trim();
    } else {
      await Process.run("cat", [path]).then((value) => process = value.stdout);
    }

    return process;
  }

  /// Execute or read [command] in terms of [type].
  // ignore: missing_return
  Future<String> getResult(String command, String type) async {
    switch (type) {
      case "FILE":
        return await this.readFile(command, true);
        break;
      case "CMD":
        return await this.commandShell(command, true);
        break;
      case "BASH":
        return await this.commandShell(command, true);
    }
  }
}
