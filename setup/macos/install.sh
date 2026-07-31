#!/bin/bash
# macOS installer for OCSInventory Agent
# LaunchDaemon plist com.ocsinventory.agent.plist (must sit next to this script).

set -euo pipefail

SILENT=${SILENT:-false}
WORKING_DIRECTORY=${WORKING_DIRECTORY:-$(cd "$(dirname "$0")" && pwd)}

### ---------- Logging ----------
log() {
	local message="$1"
	local only_file="${2:-false}"

	# nounset-safe locals
	local silent="${SILENT:-false}"
	local wd="${WORKING_DIRECTORY:-$(cd "$(dirname "$0")" && pwd)}"

	mkdir -p "$wd"

	if [[ "$silent" = false ]]; then
		if [[ "$only_file" = false ]]; then
			echo "$(date +"%Y-%m-%d %H:%M:%S") $message" | tee -a "$wd/install.log"
		else
			echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >>"$wd/install.log"
		fi
	else
		echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >>"$wd/install.log"
	fi
}

usage() {
	cat <<'USAGE'
Usage: install.sh [OPTIONS]

Options:
  -S, --silent                    Silent mode (requires --url, --username, --password)
  -U, --url URL                   OCS server URL
  -u, --username USERNAME         Username
  -p, --password PASSWORD         Password
  -m, --mode MODE                 Inventory mode (default: 1)
  -d, --data-path PATH            Data directory (default: /var/lib/ocsinventory-data)
  -l, --log-level LEVEL           Log level 0..4 (default: 3)
      --log-file                  Enable log file (default: true)
      --log-file-path PATH        Log file path (default: /var/log/ocsinventory-agent.log)
  -c, --certificate FILE          PEM certificate path (default: none)
  -b, --bypass-certificate        Bypass certificate validation (default: false)
  -s, --service                   Register LaunchDaemon
  -n, --now                       Run agent once immediately after install
  -h, --help                      Show help and exit
USAGE
	exit 1
}

execCommand() {
	local command="$1"
	local successMessage="$2"
	local errorMessage="$3"

	if $command >/dev/null 2>/dev/null; then
		log "$successMessage" false
	else
		log "$errorMessage" false
		exit 1
	fi
}

### ---------- Root check ----------
if [[ "$(id -u)" != "0" ]]; then
	log "This installer requires root privileges. Re-run with sudo." false
	exit 1
fi

### ---------- Defaults ----------
WORKING_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="/etc/ocsinventory-agent"
AGENT_DIR="/usr/local/bin"
AGENT_EXEC="/ocsinventory-cli"
DEFAULT_DATA_PATH="/var/lib/ocsinventory-data"
DEFAULT_LOG_FILE_PATH="/var/log/ocsinventory-agent.log"
PLIST_DST="/Library/LaunchDaemons/com.ocsinventory.agent.plist"
SERVICE_LABEL="com.ocsinventory.agent"

SILENT=false
URL=""
USERNAME=""
PASSWORD=""
INVENTORY_MODE=1
DATA_PATH=""
LOG_LEVEL=""
LOG_FILE=false
LOG_FILE_PATH=""
CERTIFICATE=""
BYPASS_CERTIFICATE=false
SERVICE=false
NOW=false

# arg parse
while [[ $# -gt 0 ]]; do
	case "$1" in
	-S | --silent)
		SILENT="true"
		shift
		;;
	-U | --url)
		URL="$2"
		shift 2
		;;
	-u | --username)
		USERNAME="$2"
		shift 2
		;;
	-p | --password)
		PASSWORD="$2"
		shift 2
		;;
	-m | --mode)
		INVENTORY_MODE="$2"
		shift 2
		;;
	-d | --data-path)
		DEFAULT_DATA_PATH="$2"
		shift 2
		;;
	-l | --log-level)
		LOG_LEVEL="$2"
		shift 2
		;;
	--log-file)
		LOG_FILE="true"
		shift
		;;
	--log-file-path)
		LOG_FILE_PATH="$2"
		shift 2
		;;
	-c | --certificate)
		CERTIFICATE="$2"
		shift 2
		;;
	-b | --bypass-certificate)
		BYPASS_CERTIFICATE="true"
		shift
		;;
	-s | --service)
		SERVICE="true"
		shift
		;;
	-n | --now)
		NOW="true"
		shift
		;;
	-h | --help)
		usage
		;;
	*)
		log "Unknown argument: $1" false
		usage
		;;
	esac
done

### ---------- Guards ----------
check_silent_parameters() {
	if [[ -z "$URL" ]]; then
		log "Server URL is required in silent mode" false
		usage
	fi
	if [[ -z "$USERNAME" ]]; then
		log "Username is required in silent mode" false
		usage
	fi
	if [[ -z "$PASSWORD" ]]; then
		log "Password is required in silent mode" false
		usage
	fi
	if [[ -z "$INVENTORY_MODE" ]]; then INVENTORY_MODE=1; fi
	if [[ -z "$DATA_PATH" ]]; then DATA_PATH="$DEFAULT_DATA_PATH"; fi
	if [[ -z "$LOG_LEVEL" ]]; then LOG_LEVEL=3; fi
	if [[ "${LOG_FILE}" = "false" ]]; then LOG_FILE=true; fi
	if [[ -z "$LOG_FILE_PATH" ]]; then LOG_FILE_PATH="$DEFAULT_LOG_FILE_PATH"; fi
	if [[ -z "$CERTIFICATE" ]]; then CERTIFICATE="none"; else
		execCommand "/usr/bin/openssl x509 -in \"$CERTIFICATE\" -noout" \
			"Certificate file ok: $CERTIFICATE" "Certificate not valid or unreadable: $CERTIFICATE"
	fi
	if [[ -z "${BYPASS_CERTIFICATE}" ]]; then BYPASS_CERTIFICATE=false; fi
}

### ---------- Existing install detection ----------
check_installed_agent() {
	if [ -f "$AGENT_DIR$AGENT_EXEC" ] || [ -f "${PLIST_DST}" ] || [ -d "$CONFIG_PATH" ] || [ -f "$LOG_FILE_PATH" ]; then
		if [ "$SILENT" = "true" ]; then
			log "Existing agent installation detected in silent mode. Automatically uninstalling..." false
			execCommand "sh ${WORKING_DIRECTORY}/uninstall.sh -S -D" "Existing agent uninstalled successfully. See the logs in ${WORKING_DIRECTORY}/uninstall.log" "Failed to uninstall existing agent."
		else
			echo -n "The agent is already installed, do you want to remove it first? ([y]/n) "
			read -r remove_choice

			case "$remove_choice" in
			"" | "y" | "Y")
				log "Uninstalling the existing agent..." false

				execCommand "sh ${WORKING_DIRECTORY}/uninstall.sh -S -D" "Existing agent uninstalled successfully. See the logs in ${WORKING_DIRECTORY}/uninstall.log" "Failed to uninstall existing agent."
				;;
			*)
				log "Proceeding with installation without removing the existing one. Files may be overwritten." false
				;;
			esac
		fi
	fi
}

### ---------- Install binary ----------
copy_agent_contents() {

	execCommand "cp -r $WORKING_DIRECTORY$AGENT_EXEC $AGENT_DIR" "Copied agent binary to $AGENT_DIR" "Failed to copy agent binary."

	execCommand "chmod +x $AGENT_DIR$AGENT_EXEC" "Made the agent executable: $AGENT_DIR$AGENT_EXEC" "Failed to make the agent executable."

}

### ---------- Config ----------
create_config_file() {
	log "Creating configuration file..." false

	if [ ! -d "$CONFIG_PATH" ]; then
		execCommand "mkdir -p $CONFIG_PATH" "Created configuration directory: $CONFIG_PATH" "Failed to create configuration directory."
	else
		log "Configuration directory already exists: $CONFIG_PATH" false
	fi

	if [ ! -f "$CONFIG_PATH/config.json" ]; then
		execCommand "touch $CONFIG_PATH/config.json" "Created configuration file: $CONFIG_PATH/config.json" "Failed to create configuration file."
		echo "{\"url\": \"$URL\", \"username\": \"$USERNAME\", \"password\": \"$PASSWORD\", \"mode\": $INVENTORY_MODE, \"log_level\": $LOG_LEVEL, \"log_file\": $LOG_FILE, \"log_file_path\": \"$LOG_FILE_PATH\", \"data_directory\": \"$DATA_PATH\", \"certificate\": \"$CERTIFICATE\", \"bypass-certificate\": $BYPASS_CERTIFICATE, \"execution_timeout\": 120}" >"$CONFIG_PATH/config.json"
	else
		log "Configuration file already exists: $CONFIG_PATH/config.json" false
	fi

}

### ---------- Log file ----------
create_log_file() {
	if [ "$LOG_FILE" != "true" ]; then
		log "Log file option is disabled; skipping log file creation." false
		return
	fi

	if [ -z "$LOG_FILE_PATH" ]; then
		LOG_FILE_PATH="$DEFAULT_LOG_FILE_PATH"
	fi

	log "Creating log file..." false

	if [ ! -d "$(dirname "$LOG_FILE_PATH")" ]; then
		execCommand "mkdir -p $(dirname "$LOG_FILE_PATH")" "Created log directory: $(dirname "$LOG_FILE_PATH")" "Failed to create log directory."
	else
		log "Log directory already exists: $(dirname "$LOG_FILE_PATH")" false
	fi
	if [ ! -f "$LOG_FILE_PATH" ]; then
		execCommand "touch $LOG_FILE_PATH" "Created log file: $LOG_FILE_PATH" "Failed to create log file."
	else
		log "Log file already exists: $LOG_FILE_PATH" false
	fi
}

### ---------- Data dir ----------
create_data_folder() {
	log "Creating data folder..." false

	if [ ! -d "$DATA_PATH" ]; then
		execCommand "mkdir -p $DATA_PATH" "Created data directory: $DATA_PATH" "Failed to create data directory."
	else
		log "Data directory already exists: $DATA_PATH" false
	fi
}

### ---------- One-shot execution ----------
run_executable() {
	if [ "$NOW" = "true" ]; then
		log "Running the agent now..." false
		log "Command: $AGENT_DIR$AGENT_EXEC -f $LOG_FILE -m $INVENTORY_MODE -p $PASSWORD -u $USERNAME -s $URL -l $LOG_FILE_PATH -d $DATA_PATH -v $LOG_LEVEL -c $CERTIFICATE" false

		execCommand "$AGENT_DIR$AGENT_EXEC -f $LOG_FILE -m $INVENTORY_MODE -p $PASSWORD -u $USERNAME -s $URL -l $LOG_FILE_PATH -d $DATA_PATH -v $LOG_LEVEL -c $CERTIFICATE" "Agent executed successfully." "Failed to execute the agent."
	fi
}

### ---------- LaunchDaemon (separate plist) ----------
register_service() {
	log "Installing service file..." false

	execCommand "cp ${WORKING_DIRECTORY}/com.ocsinventory.agent.plist /Library/LaunchDaemons/${SERVICE_LABEL}.plist" "Service file copied successfully." "Failed to copy service file."

	log "Reloading daemon and enabling service" false

	execCommand "launchctl bootstrap system /Library/LaunchDaemons/${SERVICE_LABEL}.plist" "LaunchDaemon bootstrapped successfully." "Failed to bootstrap LaunchDaemon."
	execCommand "launchctl enable system/com.ocsinventory.agent" "Service ${SERVICE_LABEL} enabled successfully." "Failed to enable service ${SERVICE_LABEL}."
	execCommand "launchctl kickstart -k system/com.ocsinventory.agent" "Service ${SERVICE_LABEL} started successfully." "Failed to start service ${SERVICE_LABEL}."

	log "Service Started" false
}

### ---------- Interactive flow ----------
run_interactive() {
	log "+--------------------------------------------------------------+" false
	log "|                                                              |" false
	log "|     Installing OCSInventory Agent in interactive mode...     |" false
	log "|                                                              |" false
	log "+--------------------------------------------------------------+" false
	log "" false

	check_installed_agent

	if [ -z "$URL" ]; then
		echo -n "Enter server URL: "
		read -r URL
		while :; do
			case "$URL" in
			http://* | https://*)
				break
				;;
			*)
				echo -n "Invalid URL format. Please enter a valid URL (starting with http:// or https://): "
				read -r URL
				;;
			esac
		done
		log "Server URL: $URL" true
	fi

	if [ -z "$USERNAME" ]; then
		echo -n "Enter username: "
		read -r USERNAME
		while :; do
			case "$USERNAME" in
			"" | *[!a-zA-Z0-9._-]*)
				echo -n "Invalid username format. Please enter a valid username (alphanumeric characters, dots, underscores, and hyphens allowed): "
				read -r USERNAME
				;;
			*)
				break
				;;
			esac
		done
	fi

	if [ -z "$PASSWORD" ]; then
		echo -n "Enter password: "
		read -r PASSWORD
		while [ "$PASSWORD" = "" ]; do
			echo -n "Invalid password format. Please enter a valid password (alphanumeric and special characters allowed): "
			read -r PASSWORD
		done
	fi

	if [ -z "$INVENTORY_MODE" ]; then
		echo -n "Enter the inventory mode (leave empty if default, default is 1 = Remote with template): "
		read -r INVENTORY_MODE
		if [ "$INVENTORY_MODE" = "" ]; then
			INVENTORY_MODE=1
		else
			case "$INVENTORY_MODE" in
			*[!0-9]*)
				log "Inventory mode must be a number, using default value: 1 (Remote with template)" true
				INVENTORY_MODE=1
				;;
			esac
		fi
		log "Inventory mode: $INVENTORY_MODE" true
	fi

	if [ -z "$DATA_PATH" ]; then
		echo -n "Enter the data path. Please note: the directory must be dedicated to the OCS agent (leave empty if default, default is: /var/lib/ocsinventory-data): "
		read -r DATA_PATH
		if [ "$DATA_PATH" = "" ]; then
			DATA_PATH=$DEFAULT_DATA_PATH
		fi
		log "Data path: $DEFAULT_DATA_PATH" true
	fi

	if [ -z "$LOG_LEVEL" ]; then
		echo -n "Enter the log level (leave empty if default, default is: 3 = Info): "
		read -r LOG_LEVEL
		if [ "$LOG_LEVEL" = "" ]; then
			LOG_LEVEL=3
		else
			case "$LOG_LEVEL" in
			*[!0-9]*)
				log "Log level must be a number, using default value: 3 (Info)" true
				LOG_LEVEL=3
				;;
			esac
		fi
		log "Log level: $LOG_LEVEL" true
	fi

	if [ "$LOG_FILE" = "false" ]; then
		echo -n "Do you want to enable logging to a file? ([y]/n) "
		read -r log_file_choice
		case "$log_file_choice" in
		"" | "y" | "Y")
			LOG_FILE=true
			;;
		esac
		log "Log file option: $LOG_FILE" true
	fi

	if [ "$LOG_FILE" = "true" ] && [ -z "$LOG_FILE_PATH" ]; then
		echo -n "Enter the log file path (leave empty if default, default is: /var/log/ocsinventory-agent.log): "
		read -r LOG_FILE_PATH
		if [ "$LOG_FILE_PATH" = "" ]; then
			LOG_FILE_PATH=$DEFAULT_LOG_FILE_PATH
		fi
		log "Log file path: $LOG_FILE_PATH" true
	fi

	if [ -z "$CERTIFICATE" ]; then
		echo -n "Enter the certificate path (leave empty if none): "
		read -r CERTIFICATE
		if [ "$CERTIFICATE" = "" ]; then
			CERTIFICATE="none"
		else
			execCommand "openssl x509 -in $CERTIFICATE -noout" "Certificate file exists: $CERTIFICATE" "Certificate file does not exist: $CERTIFICATE"
		fi
		log "Certificate path: $CERTIFICATE" true
	fi

	if [ "$SERVICE" = "false" ]; then
		echo -n "Should the agent be registered as a LaunchDaemon? ([y]/n) "
		read -r service_choice
		case "$service_choice" in
		"" | "y" | "Y")
			SERVICE=true
			;;
		esac
		log "Service registration: $SERVICE" true
	fi

	if [ "$NOW" = "false" ]; then
		echo -n "Do you want the agent to run immediately after installation? ([y]/n) "
		read -r now_choice
		case "$now_choice" in
		"" | "y" | "Y")
			NOW=true
			;;
		esac
		log "Run now option: $NOW" true
	fi

	copy_agent_contents
	create_config_file
	create_log_file
	create_data_folder
	run_executable
}

### ---------- Silent flow ----------
run_silent() {
	log "+---------------------------------------------------------+" false
	log "|                                                         |" false
	log "|     Installing OCSInventory Agent in silent mode...     |" false
	log "|                                                         |" false
	log "+---------------------------------------------------------+" false
	log "" false

	check_silent_parameters
	check_installed_agent
	copy_agent_contents
	create_config_file
	create_log_file
	create_data_folder
	run_executable
}

if [ "$SILENT" = "true" ]; then
	run_silent
else
	run_interactive
fi

if [ -d "$CONFIG_PATH" ] && [ -f "$LOG_FILE_PATH" ] && [ -d "$AGENT_DIR" ] && [ -f "$AGENT_DIR$AGENT_EXEC" ]; then
	if [ "$SERVICE" = "true" ]; then
		register_service
	fi
	log "" false
	log "+------------------------------------------------------------------------------------------------+" false
	log "|               OCSInventory Agent has been successfully installed and configured.               |" false
	log "|                                                                                                |" false
	log "|          Configuration files are located at $CONFIG_PATH" false
	log "|          Log file is located at $LOG_FILE_PATH" false
	log "|          Agent data storage is located at $DATA_PATH" false
	log "|          Agent installation directory is located at $AGENT_DIR" false
	log "|                                                                                                |" false
	log "|               Please refer to the documentation for more information.                          |" false
	log "+------------------------------------------------------------------------------------------------+" false

else
	log "" false
	log "*** ERROR: Installation failed ***" false
	log "" false
	log "Exiting..." false
	exit 1
fi

exit 0
