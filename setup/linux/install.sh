#!/bin/bash

log() {
	local message="$1"
	local only_file="$2"

	if [ "$SILENT" = false ]; then
		if [ "$only_file" = false ]; then
			echo "$(date +"%Y-%m-%d %H:%M:%S") $message" | tee -a "${WORKING_DIRECTORY}/install.log"
		else
			echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >>"${WORKING_DIRECTORY}/install.log"
		fi
	else
		echo "$(date +"%Y-%m-%d %H:%M:%S") $message" >>"${WORKING_DIRECTORY}/install.log"
	fi
}

usage() {
	echo "Usage: $0 [OPTIONS]"
	echo "Options:"
	echo "  -S, --silent                      Enable silent mode (requires --url, --username, --password)"
	echo "  -U, --url URL                     URL of the OCSInventory API server (required for silent mode)"
	echo "  -u, --username USERNAME           Username (required for silent mode)"
	echo "  -p, --password PASSWORD           Password (required for silent mode)"
	echo "  -m, --mode MODE                   Inventory mode (default: 1 = Remote with template)"
	echo "  -d, --data-path PATH              Path to the data directory (default: /var/lib/ocsinventory-data)"
	echo "  -l, --log-level LEVEL             Log level (default: 3 = Info)"
	echo "      --log-file                    Enable log file (default: true)"
	echo "      --log-file-path PATH          Path to the log file (default: /var/log/ocsinventory-agent.log)"
	echo "  -c, --certificate CERTIFICATE     Path to the certificate file (default: null)"
	echo "  -b, --bypass-certificate          Bypass certificate validation (default: false)"
	echo "  -s, --service                     Register the agent as a systemd service"
	echo "  -n, --now                         Run the agent inventory immediately after installation"
	echo "  -h, --help                        Display this help message"
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

check_silent_parameters() {
	if [ -z "$URL" ]; then
		log "Server URL is required in silent mode (-U, --url)" false
		usage
	fi

	if [ -z "$USERNAME" ]; then
		log "Username is required in silent mode (-u, --username)" false
		usage
	fi

	if [ -z "$PASSWORD" ]; then
		log "Password is required in silent mode (-p, --password)" false
		usage
	fi

	if [ -z "$INVENTORY_MODE" ]; then
		log "Inventory mode not provided, using default value: 1 (Remote with template)" true
		INVENTORY_MODE=1
	fi

	if [ -z "$DATA_PATH" ]; then
		log "Data path not provided, using default value: $DEFAULT_DATA_PATH" true
		DATA_PATH=$DEFAULT_DATA_PATH
	fi

	if [ -z "$LOG_LEVEL" ]; then
		log "Log level not provided, using default value: 3 (Info)" true
		LOG_LEVEL=3
	fi

	if [ "$LOG_FILE" = "false" ]; then
		log "Log file option not provided, using default value: true" true
		LOG_FILE=true
	fi

	if [ -z "$LOG_FILE_PATH" ]; then
		log "Log file path not provided, using default value: $DEFAULT_LOG_FILE_PATH" true
		LOG_FILE_PATH=$DEFAULT_LOG_FILE_PATH
	fi

	if [ -z "$CERTIFICATE" ]; then
		log "Certificate not provided, using default value: none" true
		CERTIFICATE="none"
	else
		execCommand "openssl x509 -in $CERTIFICATE -noout" "Certificate file exists: $CERTIFICATE" "Certificate file does not exist: $CERTIFICATE"
	fi

	if [ -z "$BYPASS_CERTIFICATE" ]; then
		log "Bypass certificate option not provided, using default value: false (do not bypass certificate validation)" true
		BYPASS_CERTIFICATE=false
	fi

	if [ "$NOW" = "false" ]; then
		log "Run now option not provided, using default value: false (do not run immediately)" true
	fi

	if [ "$SERVICE" = "false" ]; then
		log "Service registration not provided, using default value: false (do not register as service)" true
	fi
}

check_installed_agent() {
	if [ -f "$AGENT_BINARY$AGENT_EXEC" ] || [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ] || [ -d "$CONFIG_PATH" ] || [ -f "$LOG_FILE_PATH" ]; then
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

copy_agent_contents() {

	execCommand "cp -r $WORKING_DIRECTORY$AGENT_EXEC $AGENT_BINARY" "Copied agent binary to $AGENT_BINARY" "Failed to copy agent binary."

	execCommand "chmod +x $AGENT_BINARY$AGENT_EXEC" "Made the agent executable: $AGENT_BINARY$AGENT_EXEC" "Failed to make the agent executable."

	execCommand "ln -s $AGENT_BINARY$AGENT_EXEC $SYMBOLIC_LINK" "Created CLI symlink: $SYMBOLIC_LINK" "Failed to create CLI symlink."
}

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

create_data_folder() {
	log "Creating data folder..." false

	if [ ! -d "$DATA_PATH" ]; then
		execCommand "mkdir -p $DATA_PATH" "Created data directory: $DATA_PATH" "Failed to create data directory."
	else
		log "Data directory already exists: $DATA_PATH" false
	fi
}

run_executable() {
	if [ "$NOW" = "true" ]; then
		log "Running the agent now..." false

		local LOG_FILE_PATH_ARG=""
		if [ "$LOG_FILE_PATH" != "" ]; then
			LOG_FILE_PATH_ARG="-l $LOG_FILE_PATH"
		fi

		log "Command: $SYMBOLIC_LINK -f $LOG_FILE -m $INVENTORY_MODE -p $PASSWORD -u $USERNAME -s $URL $LOG_FILE_PATH_ARG -d $DATA_PATH -v $LOG_LEVEL -c $CERTIFICATE" false

		execCommand "$SYMBOLIC_LINK -f $LOG_FILE -m $INVENTORY_MODE -p $PASSWORD -u $USERNAME -s $URL $LOG_FILE_PATH_ARG -d $DATA_PATH -v $LOG_LEVEL -c $CERTIFICATE" "Agent executed successfully." "Failed to execute the agent."
	fi
}

register_service() {
	log "Installing systemd service..." false

	execCommand "cp ${WORKING_DIRECTORY}/${SERVICE_NAME}.service /etc/systemd/system/${SERVICE_NAME}.service" "Service file installed successfully." "Failed to install service file."

	log "Reloading daemon and enabling service" false

	execCommand "systemctl -q daemon-reload" "Systemd daemon reloaded successfully." "Failed to reload systemd daemon."

	execCommand "systemctl -q enable ${SERVICE_NAME}.service" "Service ${SERVICE_NAME} enabled successfully." "Failed to enable service ${SERVICE_NAME}."

	execCommand "systemctl -q start ${SERVICE_NAME}.service" "Service ${SERVICE_NAME} started successfully." "Failed to start service ${SERVICE_NAME}."

	log "Service Started" false
}

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
		log "Data path: $DATA_PATH" true
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
		echo -n "Enter the log file path (leave empty if default, default is: $DEFAULT_LOG_FILE_PATH): "
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
		echo -n "Should the agent be registered as a systemd service? ([y]/n) "
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

if [ "$(id -u)" != "0" ]; then
	log "The installation script requires elevated privileges, please run as root" false
	exit 1
fi

WORKING_DIRECTORY=$(dirname "$(realpath "$0")")
CONFIG_PATH="/etc/ocsinventory-agent"
AGENT_BINARY="/usr/local/bin"
SYMBOLIC_LINK="/usr/bin/ocsinventory-cli"
DEFAULT_DATA_PATH="/var/lib/ocsinventory-data"
DEFAULT_LOG_FILE_PATH="/var/log/ocsinventory-agent/ocsinventory-agent.log"
AGENT_EXEC="/ocsinventory-cli"
SERVICE_NAME="ocsinventory-agent"

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

SHORT_OPTS="SU:u:p:m:d:l:c:snh"
LONG_OPTS="silent,url:,username:,password:,mode:,data-path:,log-level:,log-file,log-file-path:,certificate:,bypass-certificate,service,now,help"

if ! PARSED_OPTIONS=$(getopt --options $SHORT_OPTS --longoptions $LONG_OPTS --name "$0" -- "$@"); then
	usage
fi

eval set -- "$PARSED_OPTIONS"
unset PARSED_OPTIONS

while true; do
	case "$1" in
	-S | --silent)
		SILENT=true
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
		LOG_FILE=true
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
		BYPASS_CERTIFICATE=true
		shift
		;;
	-s | --service)
		SERVICE=true
		shift
		;;
	-n | --now)
		NOW=true
		shift
		;;
	-h | --help)
		usage
		;;
	--)
		shift
		break
		;;
	*)
		log "Internal error!" false
		exit 1
		;;
	esac
done

if [ "$SILENT" = "true" ]; then
	run_silent
else
	run_interactive
fi

if [ -d "$CONFIG_PATH" ] && [ -d "$AGENT_BINARY" ] && [ -f "$SYMBOLIC_LINK" ]; then
	if [ "$SERVICE" = "true" ]; then
		register_service
	fi
	log "" false
	log "+------------------------------------------------------------------------------------------------+" false
	log "|               OCSInventory Agent has been successfully installed and configured.               |" false
	log "|                                                                                                |" false
	log "|          Configuration files are located at $CONFIG_PATH" false
	log "|          Log file is $([ "$LOG_FILE" = "true" ] && echo "located at $LOG_FILE_PATH" || echo "disabled")" false
	log "|          Agent data storage is located at $DATA_PATH" false
	log "|          Agent installation directory is located at $AGENT_BINARY" false
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
