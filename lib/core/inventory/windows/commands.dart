import 'dart:convert';
import 'dart:io';

/// Class for execute command on Windows.
class WindowsCommand {
  /// Execute [commandLine] to cmd.
  Future<String> commandCmd(String commandLine, bool normalization) async {
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

  /// Execute [commandLine] to powershell.
  Future<String> commandPowershell(
      String commandLine, bool normalization) async {
    List<String> args = commandLine.split(" ");
    String command = "powershell.exe";

    var process;
    if (normalization) {
      String processNormalization;
      await Process.run(command, args, stdoutEncoding: utf8)
          .then((value) => processNormalization = value.stdout);
      process = processNormalization.trim();
    } else {
      await Process.run(command, args, stdoutEncoding: utf8)
          .then((value) => process = value.stdout);
    }

    return process;
  }

  /// Return [path] file content.
  Future<String> readFile(String path, bool normalization) async {
    var process;
    if (normalization) {
      String processNormalization;
      await Process.run("type", [path])
          .then((value) => processNormalization = value.stdout);
      process = processNormalization.trim();
    } else {
      await Process.run("type", [path]).then((value) => process = value.stdout);
    }

    return process;
  }
}
