// OCSInventory Agent
// Copyright (C) OCSInventory
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

/// Admin data given at install time, stored in config.json as
/// "Name=value;Name2=value2". Matching and conversion are done by the server.
class AdminData {
  static const String pairSeparator = ";";
  static const String valueSeparator = "=";

  /// Splits [raw] on ";" then on the first "=", trimming both sides.
  /// Invalid segments are skipped and a repeated name (case ignored) keeps
  /// its last value; both are reported to [warn].
  static Map<String, String> parse(String? raw,
      {void Function(String message)? warn}) {
    Map<String, String> result = {};
    if (raw == null) return result;

    for (String segment in raw.split(pairSeparator)) {
      segment = segment.trim();
      if (segment.isEmpty) continue;

      int index = segment.indexOf(valueSeparator);
      if (index < 0) {
        warn?.call("Admin data ignored, no '=' in \"$segment\".");
        continue;
      }

      String name = segment.substring(0, index).trim();
      String value = segment.substring(index + 1).trim();
      if (name.isEmpty) {
        warn?.call("Admin data ignored, no name in \"$segment\".");
        continue;
      }

      String? previous = result.keys
          .where((key) => key.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (previous != null) {
        result.remove(previous);
        warn?.call(
            "Admin data \"$name\" given more than once, the last value is kept.");
      }
      result[name] = value;
    }

    return result;
  }
}
