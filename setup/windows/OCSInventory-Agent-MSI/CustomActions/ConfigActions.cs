using System;
using System.Collections.Generic;
using System.IO;
using System.Web.Script.Serialization;
using WixToolset.Dtf.WindowsInstaller;

namespace OCSInventoryCustomActions
{
    public static class ConfigActions
    {
        private static readonly string[] PropertyNames =
        {
            "OCS_URL",
            "OCS_USERNAME",
            "OCS_PASSWORD",
            "OCS_CERTIFICATE",
            "OCS_MODE",
            "OCS_LOG_LEVEL",
            "OCS_BYPASS_CERT",
            "OCS_ADMIN_DATA",
            "OCS_TAG",
            "INSTALLFOLDER",
        };

        // Deferred actions cannot read properties: they receive them through
        // CustomActionData, set here under the deferred action's name.
        [CustomAction]
        public static ActionResult PrepareConfig(Session session)
        {
            var data = new CustomActionData();
            foreach (var name in PropertyNames)
            {
                data[name] = session[name];
            }
            session["WriteConfig"] = data.ToString();
            return ActionResult.Success;
        }

        // Creates config.json on first installation, otherwise only updates the
        // keys of the properties given on the command line (see README.md).
        [CustomAction]
        public static ActionResult WriteConfig(Session session)
        {
            var data = session.CustomActionData;

            var updates = new Dictionary<string, object>();
            AddString(updates, data, "OCS_URL", "url");
            AddString(updates, data, "OCS_USERNAME", "username");
            AddString(updates, data, "OCS_PASSWORD", "password");
            AddString(updates, data, "OCS_CERTIFICATE", "certificate");
            if (
                !AddLevel(session, updates, data, "OCS_MODE", "mode")
                || !AddLevel(session, updates, data, "OCS_LOG_LEVEL", "log_level")
                || !AddBool(session, updates, data, "OCS_BYPASS_CERT", "bypass-certificate")
            )
            {
                return ActionResult.Failure;
            }
            updates["install_directory"] = ToSlashes(data["INSTALLFOLDER"].TrimEnd('\\'));

            var dataDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "OCSInventory-Agent"
            );
            var configPath = Path.Combine(dataDir, "config.json");
            var serializer = new JavaScriptSerializer();

            Dictionary<string, object> config = null;
            if (File.Exists(configPath))
            {
                session.Log("Updating configuration file " + configPath);
                config = ReadConfig(session, serializer, configPath);
                if (config == null)
                {
                    // Not a failure: a GPO deployment would fail silently on every
                    // machine with a broken file. It is kept aside and recreated.
                    var backupPath = configPath + ".bak";
                    File.Copy(configPath, backupPath, true);
                    session.Log(
                        "Warning: "
                            + configPath
                            + " is not a valid configuration file, saved as "
                            + backupPath
                            + " and recreated with the default values."
                    );
                }
            }
            else
            {
                session.Log("Creating configuration file " + configPath);
                Directory.CreateDirectory(dataDir);
            }
            if (config == null)
            {
                config = DefaultConfig(ToSlashes(dataDir));
            }

            // Needs the existing config: OCS_TAG alone updates its admin_data
            AddAdminData(session, updates, data, config);

            foreach (var update in updates)
            {
                config[update.Key] = update.Value;
            }
            // Key names only: values may contain the password
            session.Log("Configuration keys set: " + string.Join(", ", updates.Keys));

            object url;
            if (!config.TryGetValue("url", out url) || string.IsNullOrEmpty(url as string))
            {
                session.Log("Warning: no server url in the configuration, set OCS_URL.");
            }

            File.WriteAllText(configPath, serializer.Serialize(config));
            return ActionResult.Success;
        }

        // The JSON object of config.json, or null when the file is empty or invalid
        private static Dictionary<string, object> ReadConfig(
            Session session,
            JavaScriptSerializer serializer,
            string configPath
        )
        {
            try
            {
                return serializer.Deserialize<Dictionary<string, object>>(
                    File.ReadAllText(configPath)
                );
            }
            catch (Exception e) when (e is ArgumentException || e is InvalidOperationException)
            {
                // Invalid JSON, or JSON that is not an object (array, string...)
                session.Log("Cannot read " + configPath + ": " + e.Message);
                return null;
            }
        }

        // Same content as the file written by the Inno Setup installer
        private static Dictionary<string, object> DefaultConfig(string dataDir)
        {
            return new Dictionary<string, object>
            {
                ["url"] = "",
                ["username"] = "",
                ["password"] = "",
                ["certificate"] = "",
                ["bypass-certificate"] = false,
                ["log_file"] = true,
                ["log_level"] = 3,
                ["mode"] = 1,
                ["data_directory"] = dataDir,
                ["log_file_path"] = dataDir + "/ocsinventory-agent.log",
                ["install_directory"] = "",
                ["execution_timeout"] = 120,
            };
        }

        private static void AddString(
            Dictionary<string, object> updates,
            CustomActionData data,
            string property,
            string key
        )
        {
            if (!string.IsNullOrEmpty(data[property]))
            {
                updates[key] = data[property];
            }
        }

        private static bool AddLevel(
            Session session,
            Dictionary<string, object> updates,
            CustomActionData data,
            string property,
            string key
        )
        {
            var value = data[property];
            if (string.IsNullOrEmpty(value))
            {
                return true;
            }
            if (!int.TryParse(value, out var level) || level < 0 || level > 4)
            {
                session.Log(property + " must be between 0 and 4, got '" + value + "'.");
                return false;
            }
            updates[key] = level;
            return true;
        }

        private static bool AddBool(
            Session session,
            Dictionary<string, object> updates,
            CustomActionData data,
            string property,
            string key
        )
        {
            var value = data[property];
            if (string.IsNullOrEmpty(value))
            {
                return true;
            }
            switch (value.ToLowerInvariant())
            {
                case "1":
                case "true":
                    updates[key] = true;
                    return true;
                case "0":
                case "false":
                    updates[key] = false;
                    return true;
                default:
                    session.Log(property + " must be 0, 1, true or false, got '" + value + "'.");
                    return false;
            }
        }

        // admin_data is "Name=value;Name2=value2", parsed by the agent (admin_data.dart).
        // OCS_ADMIN_DATA replaces it, plus TAG=<OCS_TAG> unless it already sets TAG
        // (as /ADMIN_DATA and /TAG of the .exe). OCS_TAG alone only sets the TAG
        // pair of the existing value, keeping the other pairs.
        private static void AddAdminData(
            Session session,
            Dictionary<string, object> updates,
            CustomActionData data,
            Dictionary<string, object> config
        )
        {
            var adminData = (data["OCS_ADMIN_DATA"] ?? "").Trim();
            var tag = (data["OCS_TAG"] ?? "").Trim();

            if (adminData.Length > 0)
            {
                if (tag.Length > 0 && !AdminDataSetsTag(adminData))
                {
                    adminData = adminData + ";TAG=" + tag;
                }
            }
            else if (tag.Length > 0)
            {
                object existing;
                config.TryGetValue("admin_data", out existing);
                if (existing != null && !(existing is string))
                {
                    // Ignored by the agent anyway (admin_data must be a string)
                    session.Log("Warning: admin_data is not a string in config.json, replaced.");
                }
                adminData = WithTag(existing as string ?? "", tag);
            }
            else
            {
                return;
            }

            updates["admin_data"] = adminData;
            session.Log("Administrative data: " + adminData);
        }

        private static bool AdminDataSetsTag(string adminData)
        {
            foreach (var segment in adminData.Split(';'))
            {
                if (IsTagPair(segment))
                {
                    return true;
                }
            }
            return false;
        }

        // adminData without its TAG pairs and empty segments, then TAG=<tag>
        private static string WithTag(string adminData, string tag)
        {
            var pairs = new List<string>();
            foreach (var segment in adminData.Split(';'))
            {
                if (segment.Trim().Length > 0 && !IsTagPair(segment))
                {
                    pairs.Add(segment.Trim());
                }
            }
            pairs.Add("TAG=" + tag);
            return string.Join(";", pairs);
        }

        // Name compared case-insensitively, as the agent and the server do
        private static bool IsTagPair(string segment)
        {
            var index = segment.IndexOf('=');
            return index >= 0
                && string.Equals(
                    segment.Substring(0, index).Trim(),
                    "TAG",
                    StringComparison.OrdinalIgnoreCase
                );
        }

        // The agent and the Inno Setup installer use forward slashes in config.json
        private static string ToSlashes(string path)
        {
            return path.Replace('\\', '/');
        }
    }
}
