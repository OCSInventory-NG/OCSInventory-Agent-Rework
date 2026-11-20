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
            "OCS_URL", "OCS_USERNAME", "OCS_PASSWORD", "OCS_CERTIFICATE",
            "OCS_MODE", "OCS_LOG_LEVEL", "OCS_BYPASS_CERT", "INSTALLFOLDER",
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
            if (!AddLevel(session, updates, data, "OCS_MODE", "mode")
                || !AddLevel(session, updates, data, "OCS_LOG_LEVEL", "log_level")
                || !AddBool(session, updates, data, "OCS_BYPASS_CERT", "bypass-certificate"))
            {
                return ActionResult.Failure;
            }
            updates["install_directory"] = ToSlashes(data["INSTALLFOLDER"].TrimEnd('\\'));

            var dataDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "OCSInventory-Agent");
            var configPath = Path.Combine(dataDir, "config.json");
            var serializer = new JavaScriptSerializer();

            Dictionary<string, object> config;
            if (File.Exists(configPath))
            {
                session.Log("Updating configuration file " + configPath);
                config = serializer.Deserialize<Dictionary<string, object>>(File.ReadAllText(configPath));
                if (config == null)
                {
                    throw new InvalidDataException(configPath + " does not contain a JSON object.");
                }
            }
            else
            {
                session.Log("Creating configuration file " + configPath);
                Directory.CreateDirectory(dataDir);
                config = DefaultConfig(ToSlashes(dataDir));
            }

            foreach (var update in updates)
            {
                config[update.Key] = update.Value;
            }
            // Key names only: values may contain the password
            session.Log("Configuration keys set: " + string.Join(", ", updates.Keys));

            File.WriteAllText(configPath, serializer.Serialize(config));
            return ActionResult.Success;
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

        private static void AddString(Dictionary<string, object> updates, CustomActionData data, string property, string key)
        {
            if (!string.IsNullOrEmpty(data[property]))
            {
                updates[key] = data[property];
            }
        }

        private static bool AddLevel(Session session, Dictionary<string, object> updates, CustomActionData data, string property, string key)
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

        private static bool AddBool(Session session, Dictionary<string, object> updates, CustomActionData data, string property, string key)
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

        // The agent and the Inno Setup installer use forward slashes in config.json
        private static string ToSlashes(string path)
        {
            return path.Replace('\\', '/');
        }
    }
}
