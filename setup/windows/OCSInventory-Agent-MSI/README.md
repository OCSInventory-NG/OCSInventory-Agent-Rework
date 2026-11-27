# OCS Inventory Agent MSI

Windows Installer package of the agent, meant for mass deployment (GPO, `msiexec`).
It is built from the same binaries as the Inno Setup installer (`OCSInventory-Agent-Setup`):

- `ocsinventory-agent.exe` (Dart agent)
- `OCSInventory-Service.exe` (.NET 9 self-contained service)

Published asset: `OCSInventory-Agent-Setup-Windows-<tag>.msi`.

## Build

Requirements: Windows, the .NET SDK (the WiX v5 SDK is downloaded by NuGet).

1. Build the payload with `setup\windows\build_all.bat` (see the main README).
2. Build the MSI, `AgentVersion` being the numeric version (see [Version](#version)):

```batch
dotnet build setup\windows\OCSInventory-Agent-MSI\OCSInventory-Agent-MSI.wixproj -c Release --no-incremental -p:AgentVersion=3.1.0
```

`--no-incremental` is needed when only `AgentVersion` changes: otherwise MSBuild considers the package up to date and keeps the previous version.

The package `OCSInventory-Agent-Setup.msi` is created under `setup\windows\OCSInventory-Agent-MSI\bin\`.

Files:

- `Package.wxs`: files, service, upgrades, launch conditions.
- `CustomActions/`: custom actions (C#, .NET Framework) writing `config.json` and removing an `.exe` installation.

## Public properties

| Property          | `.exe` equivalent | Values                 | Default                                     | Notes                                        |
|-------------------|-------------------|------------------------|---------------------------------------------|----------------------------------------------|
| `OCS_URL`         | `/URL=`           | server URL             | —                                           | required unless `config.json` already exists |
| `OCS_USERNAME`    | `/USERNAME=`      | text                   | —                                           | `USERNAME` is reserved by Windows Installer  |
| `OCS_PASSWORD`    | `/PASSWORD=`      | text                   | —                                           | hidden, never written to the MSI log         |
| `OCS_CERTIFICATE` | `/CERTIFICATE=`   | path                   | —                                           | the file must exist on the machine           |
| `OCS_MODE`        | `/MODE=`          | `0`-`4`                | `1`                                         |                                              |
| `OCS_LOG_LEVEL`   | `/LOG_LEVEL=`     | `0`-`4`                | `3`                                         |                                              |
| `OCS_BYPASS_CERT` | `/BYPASS_CERT=`   | `0`/`1`/`true`/`false` | `0`                                         |                                              |
| `OCS_ADMIN_DATA`  | `/ADMIN_DATA=`    | `Name=value;Name2=...` | —                                           | see [Administrative data](#administrative-data) |
| `OCS_TAG`         | `/TAG=`           | text                   | —                                           | see [Administrative data](#administrative-data) |
| `INSTALLFOLDER`   | `/DIR=`           | path                   | `[ProgramFiles64Folder]OCS Inventory Agent` |                                              |

Not supported: `/SERVICE=` (the service is always installed) and `/NOW=` (the service starts the agent).
Silent mode uses the standard `msiexec` options (`/qn`).

## Configuration file

`C:\ProgramData\OCSInventory-Agent\config.json`, same format as the Inno Setup installer.

- First installation: the file is created from the `OCS_*` properties, defaults applying to missing ones.
- Upgrade or reinstallation: the existing file is kept. Only the keys of the properties given on the command line are updated. `install_directory` is always updated.
- Uninstallation: `C:\ProgramData\OCSInventory-Agent` is kept.
- A property given empty is ignored: a value cannot be cleared from the command line (edit `config.json` instead).

### Administrative data

Saved in the `admin_data` key, see *Administrative data* in the main README for the format and how the server uses it.

| Properties given                                | `admin_data` written                                                     |
|-------------------------------------------------|--------------------------------------------------------------------------|
| `OCS_ADMIN_DATA`                                | `OCS_ADMIN_DATA`, replacing the existing value                           |
| `OCS_ADMIN_DATA` and `OCS_TAG`                  | `OCS_ADMIN_DATA` plus `TAG=<OCS_TAG>`, unless `OCS_ADMIN_DATA` sets `TAG` |
| `OCS_TAG` only                                  | existing value with its `TAG` pair set to `OCS_TAG`, other pairs kept    |
| none                                            | unchanged                                                                |

Example: with `admin_data` set to `Site=Paris;TAG=old`, an upgrade with `OCS_TAG=client1` gives `Site=Paris;TAG=client1`.

## Service

- Name: `OCSInventory Agent` (same as the Inno Setup installer).
- Startup type: automatic, started at the end of the installation.
- Removed on uninstallation.

## Upgrades

- A newer MSI replaces the installed one: a single "OCS Inventory Agent" entry remains.
- An older MSI is refused (downgrade).
- An existing installation made with the `.exe` installer is uninstalled silently; `config.json` is kept.
  The service is stopped first, then the installation waits (up to 2 minutes each) for the `.exe` uninstallation to end and for the service to be deleted.
  A service kept "marked for deletion" by an open handle (`services.msc`...) makes the installation fail, see [Exit codes](#exit-codes).

### Version

An MSI only accepts a numeric `major.minor.build` version. The pre-release suffix of the tag is dropped:

| Tag         | MSI version |
|-------------|-------------|
| `3.1.0-rc1` | `3.1.0`     |
| `3.1.0`     | `3.1.0`     |

Installing the same version again replaces the installed one, so `3.1.0` replaces `3.1.0-rc1`.
As a consequence, `3.1.0-rc1` installed over `3.1.0` also replaces it instead of being refused.
The file name keeps the full tag (`OCSInventory-Agent-Setup-Windows-3.1.0-rc1.msi`).

## Examples

```text
msiexec /i OCSInventory-Agent-Setup-Windows-3.1.0.msi /qn /l*v C:\Windows\Temp\ocs-agent.log ^
OCS_URL=https://ocs.example.org OCS_USERNAME=agent OCS_PASSWORD=secret OCS_MODE=1

msiexec /i OCSInventory-Agent-Setup-Windows-3.1.0.msi /qn ^
OCS_URL=https://ocs.example.org OCS_ADMIN_DATA="Site=Paris;Usage=Office,Dev" OCS_TAG=client1

msiexec /i OCSInventory-Agent-Setup-Windows-3.1.0.msi /qn TRANSFORMS=ocs-agent.mst

msiexec /x OCSInventory-Agent-Setup-Windows-3.1.0.msi /qn
```

## Exit codes

| Case                                               | Code                                                                  |
|----------------------------------------------------|-----------------------------------------------------------------------|
| Success                                            | `0`                                                                   |
| Success, reboot required                           | `3010`                                                                |
| Launch condition not met (no `OCS_URL`, downgrade) | `1603`, with the reason in the log                                    |
| `.exe` installation not removed (service still present, uninstaller timeout) | `1603`, with the reason in the log: close `services.msc` or reboot, then retry |
| 32-bit Windows                                     | `1633` (the package is x64 only, refused by Windows Installer itself) |

## Open points

- `OCS_CERTIFICATE` with GPO deployment: the certificate file has to be present on each machine before installation. How it gets there is not defined yet.
