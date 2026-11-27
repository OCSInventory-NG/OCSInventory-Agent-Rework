using System;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;
using System.Threading;
using Microsoft.Win32;
using WixToolset.Dtf.WindowsInstaller;

namespace OCSInventoryCustomActions
{
    // Silent removal of an installation made with the Inno Setup .exe (see README.md, Upgrades).
    // Its uninstaller runs "sc stop" then "sc delete" without waiting for the service to stop:
    // the service can still be marked for deletion when InstallServices creates it again
    // (error 1072). The service is therefore stopped first, and the removal is awaited.
    public static class InnoMigration
    {
        private static readonly TimeSpan StopTimeout = TimeSpan.FromSeconds(120);
        private static readonly TimeSpan RemovalTimeout = TimeSpan.FromSeconds(120);
        private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1);

        // Deferred actions cannot read properties, see ConfigActions.PrepareConfig
        [CustomAction]
        public static ActionResult PrepareUninstallInno(Session session)
        {
            var data = new CustomActionData();
            data["UNINSTALL_STRING"] = session["INNO_UNINSTALL_STRING"];
            data["UNINSTALL_KEY"] = session["INNO_UNINSTALL_KEY"];
            data["SERVICE_NAME"] = session["AGENT_SERVICE_NAME"];
            session["UninstallInno"] = data.ToString();
            return ActionResult.Success;
        }

        [CustomAction]
        public static ActionResult UninstallInno(Session session)
        {
            var data = session.CustomActionData;
            var serviceName = data["SERVICE_NAME"];
            var uninstallKey = data["UNINSTALL_KEY"];

            if (!StopService(session, serviceName))
            {
                return ActionResult.Failure;
            }

            string exe,
                args;
            SplitCommand(data["UNINSTALL_STRING"], out exe, out args);
            args = (args + " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART").Trim();
            session.Log("Running the Inno Setup uninstaller: \"" + exe + "\" " + args);
            using (
                var process = Process.Start(
                    new ProcessStartInfo(exe, args) { UseShellExecute = false }
                )
            )
            {
                process.WaitForExit();
                session.Log("Inno Setup uninstaller exit code: " + process.ExitCode);
            }

            // The uninstaller runs again from a temporary copy: wait for the end of the
            // uninstallation, not only for the process started above.
            if (!WaitFor(() => !UninstallKeyExists(uninstallKey), RemovalTimeout))
            {
                session.Log(
                    "The Inno Setup installation is still registered after "
                        + RemovalTimeout.TotalSeconds
                        + "s: HKLM\\"
                        + uninstallKey
                );
                return ActionResult.Failure;
            }
            if (!WaitFor(() => !File.Exists(exe), RemovalTimeout))
            {
                // Not blocking: Inno Setup may leave it to be deleted at the next reboot
                session.Log("Warning: the Inno Setup uninstaller is still present: " + exe);
            }

            // A service marked for deletion is only deleted once every handle on it is
            // closed (services.msc, Task Manager...)
            if (!WaitFor(() => !ServiceExists(serviceName), RemovalTimeout))
            {
                session.Log(
                    "The service '"
                        + serviceName
                        + "' still exists after the Inno Setup uninstallation, it may be"
                        + " marked for deletion: close services.msc and retry, or reboot."
                );
                return ActionResult.Failure;
            }

            session.Log("Inno Setup installation removed.");
            return ActionResult.Success;
        }

        private static bool StopService(Session session, string serviceName)
        {
            var service = FindService(serviceName);
            if (service == null)
            {
                session.Log("Service '" + serviceName + "' not installed.");
                return true;
            }

            using (service)
            {
                try
                {
                    if (service.Status == ServiceControllerStatus.Stopped)
                    {
                        return true;
                    }
                    if (service.Status != ServiceControllerStatus.StopPending)
                    {
                        session.Log("Stopping the service '" + serviceName + "'.");
                        service.Stop();
                    }
                    service.WaitForStatus(ServiceControllerStatus.Stopped, StopTimeout);
                    session.Log("Service '" + serviceName + "' stopped.");
                    return true;
                }
                catch (System.ServiceProcess.TimeoutException)
                {
                    session.Log(
                        "The service '"
                            + serviceName
                            + "' did not stop within "
                            + StopTimeout.TotalSeconds
                            + "s."
                    );
                    return false;
                }
                catch (InvalidOperationException e)
                {
                    session.Log("Cannot stop the service '" + serviceName + "': " + e.Message);
                    return false;
                }
            }
        }

        private static ServiceController FindService(string serviceName)
        {
            ServiceController found = null;
            foreach (var service in ServiceController.GetServices())
            {
                if (
                    found == null
                    && string.Equals(
                        service.ServiceName,
                        serviceName,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    found = service;
                }
                else
                {
                    service.Dispose();
                }
            }
            return found;
        }

        private static bool ServiceExists(string serviceName)
        {
            using (var service = FindService(serviceName))
            {
                return service != null;
            }
        }

        // The Inno Setup uninstall key is in the 64-bit view (64-bit install mode)
        private static bool UninstallKeyExists(string uninstallKey)
        {
            using (
                var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)
            )
            using (var key = hklm.OpenSubKey(uninstallKey))
            {
                return key != null;
            }
        }

        private static bool WaitFor(Func<bool> condition, TimeSpan timeout)
        {
            var watch = Stopwatch.StartNew();
            while (!condition())
            {
                if (watch.Elapsed >= timeout)
                {
                    return false;
                }
                Thread.Sleep(PollInterval);
            }
            return true;
        }

        // UninstallString is "C:\...\unins000.exe" (quoted), possibly followed by arguments
        private static void SplitCommand(string command, out string exe, out string args)
        {
            command = (command ?? "").Trim();
            if (command.StartsWith("\""))
            {
                var end = command.IndexOf('"', 1);
                if (end > 0)
                {
                    exe = command.Substring(1, end - 1);
                    args = command.Substring(end + 1).Trim();
                    return;
                }
            }
            exe = command.Trim('"');
            args = "";
        }
    }
}
