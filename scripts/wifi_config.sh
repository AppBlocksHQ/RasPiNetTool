#!/bin/bash -m

# Handle Ctrl+C gracefully
trap 'echo -e "\r\nWiFi configuration canceled. Returning to main menu...\r\n"; exit 0' SIGINT

#---CONSTANTS
AUTO="auto"
DONE="DONE"
MANUAL="manual"
NIC_TYPE="wifi"
NIC_NAME="wlan0"
METRIC_VAL="10"
NEWCONFIG="wlan0-persistent"
NEWCONFIGNAME="${NEWCONFIG}.nmconnection"
NETWORKMANAGER_DIR="/etc/NetworkManager"
CONF_D_DIR="${NETWORKMANAGER_DIR}/conf.d"
SYSTEMCONNECTIONS_DIR="${NETWORKMANAGER_DIR}/system-connections"

POWERSAVE_CONF_FPATH="${CONF_D_DIR}/powersave.conf"

SECURITY_TYPE="wpa-psk"  # WPA2 Personal security type
WIFI_MODE="infrastructure"  # Standard WiFi mode
NO_CARRIER="NO-CARRIER"

INPUT_STATIC_IP="Enter STATIC-IP (e.g., 192.168.1.100/24)"
INPUT_GATEWAY="Enter Gateway IP (e.g., 192.168.1.1)"
INPUT_DNS="Enter DNS IP (e.g., 8.8.8.8)"
INPUT_METRIC="Enter Metric value"
INPUT_SSID="Enter WiFi SSID"
INPUT_PASSPHRASE="Enter WiFi Passphrase"

#---VARIABLES
currConfig=""
newConfigFileIsCreated=false
networkConfigIsChanged=false
noCarrierIsDetected=false


#---FUNCTIONS
checkIfRootOrSudoer() {
    echo -e "\r"
    if [[ "${EUID}" -ne 0 ]]; then
        echo "***[DENIED]: This script must be run as root or with sudo."
        echo -e "\r"
        exit 1
    fi
}


validateIpAddress() {
    local ip=${1}
    local stat=1

    if [[ ${ip} == "" ]]; then
        echo "***[ERROR]: IP address cannot be empty" >&2
        return 1
    fi

    # Split IP and subnet mask
    local ip_part=${ip%/*}
    local mask_part=${ip#*/}

    # Check for 0.0.0.0
    if [[ ${ip_part} == "0.0.0.0" ]]; then
        echo "***[ERROR]: IP address cannot be 0.0.0.0" >&2
        return 1
    fi

    # Validate IP part
    if [[ ${ip_part} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=${IFS}
        IFS='.'
        ip_part=(${ip_part})
        IFS=${OIFS}
        
        # Check last octet is not 0 or 255
        if [[ ${ip_part[3]} -eq 0 || ${ip_part[3]} -eq 255 ]]; then
            echo "***[ERROR]: Last octet cannot be 0 or 255" >&2
            return 1
        fi
        
        [[ ${ip_part[0]} -le 255 && ${ip_part[1]} -le 255 \
            && ${ip_part[2]} -le 255 && ${ip_part[3]} -le 255 ]]
        stat=${?}
    else
        echo "***[ERROR]: Invalid IP address format. Must be in format: 192.168.1.100/24" >&2
        return 1
    fi

    # If IP part is valid, validate subnet mask
    if [[ ${stat} -eq 0 ]]; then
        if [[ ${mask_part} =~ ^[0-9]+$ ]] && [[ ${mask_part} -ge 0 ]] && [[ ${mask_part} -le 32 ]]; then
            return 0
        else
            echo "***[ERROR]: Invalid subnet mask. Must be between 0 and 32" >&2
            return 1
        fi
    fi

    return ${stat}
}

validateSimpleIpAddress() {
    local ip=${1}
    local stat=1

    if [[ ${ip} == "" ]]; then
        echo "***[ERROR]: IP address cannot be empty" >&2
        return 1
    fi

    # Check for 0.0.0.0
    if [[ ${ip} == "0.0.0.0" ]]; then
        echo "***[ERROR]: IP address cannot be 0.0.0.0" >&2
        return 1
    fi

    if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=${IFS}
        IFS='.'
        ip=(${ip})
        IFS=${OIFS}
        
        # Check last octet is not 0 or 255
        if [[ ${ip[3]} -eq 0 || ${ip[3]} -eq 255 ]]; then
            echo "***[ERROR]: Last octet cannot be 0 or 255" >&2
            return 1
        fi
        
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=${?}
        if [[ ${stat} -eq 0 ]]; then
            return 0
        else
            echo "***[ERROR]: Invalid IP address. Each octet must be between 0 and 255" >&2
            return 1
        fi
    else
        echo "***[ERROR]: Invalid IP address format. Must be in format: 192.168.1.1" >&2
        return 1
    fi
}

validateNumeric() {
    local num=${1}

    if [[ ${num} == "" ]]; then
        echo "***[ERROR]: Value cannot be empty" >&2
        return 1
    fi

    if [[ ${num} =~ ^[0-9]+$ ]]; then
        return 0
    else
        echo "***[ERROR]: Value must be a number" >&2
        return 1
    fi
}

validateSSID() {
    local ssid=${1}

    if [[ ${ssid} == "" ]]; then
        echo "***[ERROR]: SSID cannot be empty" >&2
        return 1
    fi

    if [[ ${#ssid} -gt 32 ]]; then
        echo "***[ERROR]: SSID must be 32 characters or less" >&2
        return 1
    fi

    return 0
}

validatePassphrase() {
    local pass=${1}

    if [[ ${pass} == "" ]]; then
        echo "***[ERROR]: Passphrase cannot be empty" >&2
        return 1
    fi

    if [[ ${#pass} -lt 8 ]]; then
        echo "***[ERROR]: Passphrase must be at least 8 characters" >&2
        return 1
    fi

    if [[ ${#pass} -gt 63 ]]; then
        echo "***[ERROR]: Passphrase must be 63 characters or less" >&2
        return 1
    fi

    return 0
}

validateIpAddressInUse() {
    local ip=${1}
    local ip_part=${ip%/*}
    
    # Check if IP is already in use
    if ip a | grep -v "${NIC_NAME}" | grep -q "inet ${ip_part}/"; then
        echo "***[ERROR]: IP address ${ip_part} is already in use on this system" >&2
        return 1
    fi
    return 0
}

validateMetricInUse() {
    local metric=${1}
    
    # Check if metric is already in use
    if ip route show default | grep -v "${NIC_NAME}" | grep -q "metric ${metric}"; then
        echo "***[ERROR]: Metric ${metric} is already in use by another route" >&2
        return 1
    fi
    return 0
}

validateGatewayInSubnet() {
    local ip_cidr=${1}
    local gateway=${2}

    # Extract IP and subnet mask length
    local ip=${ip_cidr%/*}
    local masklen=${ip_cidr#*/}

    # Convert IPs to integers
    ip_to_int() {
        local ip=$1
        local a b c d
        IFS=. read -r a b c d <<< "$ip"
        
        echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
    }

    local ip_int=$(ip_to_int "${ip}")
    local gw_int=$(ip_to_int "${gateway}")

    # Create subnet mask from mask length
    local mask=$(( 0xFFFFFFFF << (32 - masklen) & 0xFFFFFFFF ))

    # Apply mask and compare
    if (( (ip_int & mask) != (gw_int & mask) )); then
        echo "***[ERROR]: Gateway ${gateway} is not in the same subnet as ${ip}/${masklen}" >&2
        return 1
    fi
    return 0
}

getValidInput() {
    local readinputPrompt=${1}
    local validationFuncName=${2}
    local input=""
    local isValid=0
    
    while [[ ${isValid} -eq 0 ]]; do
        read -e -p "${readinputPrompt}: " input
        if ${validationFuncName} "${input}"; then
            isValid=1
        fi
    done
    
    echo "${input}"
}

showCurrentNmcliConfig() {
    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    Current Nmcli Connection Info"
    echo "---------------------------------------------------------------------"
    nmcli connection show
    echo "---------------------------------------------------------------------"

    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    ${NEWCONFIGNAME}-content Info"
    echo "---------------------------------------------------------------------"
    sudo cat ${SYSTEMCONNECTIONS_DIR}/${NEWCONFIGNAME}
    echo "---------------------------------------------------------------------"
}

showWifiInfo() {
    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    WiFi Info for ${NIC_NAME}"
    echo "---------------------------------------------------------------------"
    iwconfig ${NIC_NAME}
    echo "---------------------------------------------------------------------"
}

showNetworkInfo() {
    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    Network Info for ${NIC_NAME}"
    echo "---------------------------------------------------------------------"
    ifconfig ${NIC_NAME}
    echo "---------------------------------------------------------------------"
    echo -e "\r"
}

showSSID() {
    sudo nmcli dev wifi rescan
    sleep 1

    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    SSID for ${NIC_NAME}"
    echo "---------------------------------------------------------------------"
    PAGER= nmcli dev wifi list
    echo "---------------------------------------------------------------------"
    echo -e "\r"
}

disableStopUserConfigService() {
    # Check if the service is active
    if systemctl is-active --quiet userconfig.service; then
        echo "---[STATUS]: Stopping userconfig.service..."
        sudo systemctl stop userconfig.service
    fi

    # Check if the service is enabled
    if systemctl is-enabled --quiet userconfig.service; then
        echo "---[STATUS]: Disabling userconfig.service..."
        sudo systemctl disable userconfig.service
    fi
}

disablePowerSavingMode() {
    # Initialize flag
    local reqRestart=false
    
    # Check if the directory exists
    if [[ -f "${POWERSAVE_CONF_FPATH}" ]]; then
        echo "---[STATUS]: Checking if ${POWERSAVE_CONF_FPATH} contains 'wifi.powersave = 2'"
        if grep -q "wifi.powersave = 2" "${POWERSAVE_CONF_FPATH}"; then
            echo "---[STATUS]: ${POWERSAVE_CONF_FPATH} already contains 'wifi.powersave = 2'"
        else
            echo "---[STATUS]: ${POWERSAVE_CONF_FPATH} does not contain 'wifi.powersave = 2'"
            echo "---[STATUS]: Removing ${POWERSAVE_CONF_FPATH} file..."
            sudo rm -f "${POWERSAVE_CONF_FPATH}"

            echo "---[STATUS]: Creating ${POWERSAVE_CONF_FPATH} file..."
            echo "[connection]" | sudo tee "${POWERSAVE_CONF_FPATH}"
            echo "wifi.powersave = 2" | sudo tee -a "${POWERSAVE_CONF_FPATH}"

            reqRestart=true
        fi
    else
        echo "---[STATUS]: ${POWERSAVE_CONF_FPATH} does not exist"
        echo "---[STATUS]: Creating ${POWERSAVE_CONF_FPATH} file..."
        echo "[connection]" | sudo tee "${POWERSAVE_CONF_FPATH}"
        echo "wifi.powersave = 2" | sudo tee -a "${POWERSAVE_CONF_FPATH}"

        reqRestart=true
    fi
    
    if [[ ${reqRestart} == true ]]; then
        echo "---[STATUS]: Restarting NetworkManager..."
        sudo systemctl restart NetworkManager

        # Wait for wlan0 to appear in nmcli connection show with 10 second timeout
        local timeout=10
        echo "---[STATUS]: Waiting for ${NIC_NAME} to appear in NetworkManager connections (max ${timeout} seconds)..."
        local counter=0
        while ! nmcli connection show | grep -q "${NIC_NAME}"; do
            counter=$((counter + 1))
            local dots=$(printf '%*s' ${counter} | tr ' ' '.')
            echo -ne "\rWaiting${dots}   \r"
            sleep 1
            
            if [ ${counter} -ge ${timeout} ]; then
                echo -e "\r                                                            \r"
                echo "***[WARNING]: Timeout waiting for ${NIC_NAME} to appear in NetworkManager connections after ${timeout} seconds"
                break
            fi
        done

        if [ ${counter} -lt ${timeout} ]; then
            echo -e "\r                                                            \r"
            echo "---[STATUS]: ${NIC_NAME} is now available in NetworkManager connections"

            echo "---[STATUS]: Waiting for ${NIC_NAME} to establish carrier..."
            local maxWaitTime=30
            local carrierCounter=0
            
            while [[ ${carrierCounter} -lt ${maxWaitTime} ]]; do
                if ! ip link show ${NIC_NAME} | grep -q "${NO_CARRIER}"; then
                    echo -e "\r                                                            \r"
                    echo "---[INFO]: ${NIC_NAME} has established carrier after ${carrierCounter} seconds"
                    noCarrierIsDetected=false
                    break
                fi
                
                carrierCounter=$((carrierCounter + 1))
                local dots=$(printf '%*s' ${carrierCounter} | tr ' ' '.')
                echo -ne "\rWaiting${dots}   \r"
                sleep 1
            done
            
            echo -e "\r                                                            \r" # Clear the dot line
            
            if [[ ${carrierCounter} -ge ${maxWaitTime} ]]; then
                echo "---[WARNING]: ${NIC_NAME} did not establish carrier after ${maxWaitTime} seconds"
                echo "---[STATUS]: Continuing anyway..."
                noCarrierIsDetected=true
            fi
        fi
    fi
}

checkIfWifiHasCarrier() {
    # Flag could have been set by function 'disableStopUserConfigService'
    if [[ ${noCarrierIsDetected} == true ]]; then
        return 1
    fi

    local result=$(ip link show ${NIC_NAME} | grep "${NO_CARRIER}")
    if [[ -n "${result}" ]]; then
        echo "---[STATUS]: ${NIC_NAME} does NOT have a carrier"

        return 1
    else
        echo "---[STATUS]: ${NIC_NAME} has a carrier"

        return 0
    fi
}

cleanUpExistingConfig() {
    ##########################################################################################
    # NOTE: this function will delete all existing WiFi configurations for the given NIC_NAME
    ##########################################################################################
    echo "---[STATUS]: Cleaning up existing WiFi configurations..."
    
    # Get all WiFi connections
    local result=$(nmcli connection show  | grep "${NIC_NAME}")
    
    # Check if there are any WiFi connections
    if [[ -z "${result}" ]]; then
        echo "---[INFO]: No existing WiFi configurations found."
        return 0
    fi
    
    # Process the results line by line
    while IFS= read -r line; do
        # Extract the NAME column using the same method as currConfig
        local conn=$(echo "${line}" | sed -E 's/[[:space:]]{2,}/ /g' | awk '{$NF=""; $(NF-1)=""; $(NF-2)=""; sub(/[[:space:]]+$/, ""); print}')
        
        echo "---[INFO]: Found WiFi configuration: ${conn}"
        
        # Delete the connection
        echo "---[STATUS]: Deleting connection '${conn}'..."
        sudo nmcli connection delete "${conn}"
        
        # Get normalized filename (NetworkManager may convert spaces to hyphens)
        local connFile="${SYSTEMCONNECTIONS_DIR}/${conn// /-}.nmconnection"
        
        # Delete the configuration file if it exists
        if [[ -f "${connFile}" ]]; then
            echo "---[STATUS]: Deleting configuration file '${connFile}'..."
            sudo rm -f "${connFile}"
        fi
    done <<< "${result}"
    
    echo "---[STATUS]: Cleanup complete."
    echo -e "\r"
}

retrieveNmcliConfigName() {
    if ! checkIfWifiHasCarrier; then
        echo -e "\r"
        echo "---[INFO]: NO-CARRIER was detected for ${NIC_NAME}"
        
        local answer=""
        while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
            read -e -p "Connect wifi to another SSID? (y/n): " answer
            if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
                echo -e "\r"
                echo "***[ERROR]: Please enter y, Y, n, or N only."
                echo -e "\r"
            fi
        done

        if [[ "${answer,,}" =~ ^[y]$ ]]; then
            cleanUpExistingConfig
            currConfig=""
            return 0
        else
            echo -e "\r"
            echo "---[STATUS]: Exiting WiFi Configuration..."
            echo -e "\r"
            sleep 1
            exit 0
        fi
    fi

    echo "---[STATUS]: retrieving the current Nmcli WiFi Configuration..."

    # Get the result from nmcli and filter by nicName
    local result=$(nmcli connection show | grep "${NIC_NAME}")

    # Extract the NAME column (everything before the UUID)
    currConfig=$(echo "${result}" | sed -E 's/[[:space:]]{2,}/ /g' | awk '{$NF=""; $(NF-1)=""; $(NF-2)=""; sub(/[[:space:]]+$/, ""); print}')

    echo "---[FOUND]: ...${currConfig}"
}

writeNmcliConfigToFile() {
    echo "---[STATUS]: Checking if Nmcli WiFi Configuration ${currConfig} already exists..."

    # If the current config is not found, create a new one
    if [[ -z "${currConfig}" ]]; then
        echo "---[INFO]: No Nmcli WiFi Configuration found for ${NIC_NAME}."
        echo "---[STATUS]: Creating new Nmcli WiFi Configuration with the following parameters:"
        echo "---[INFO]: Config-name: ${NEWCONFIG}"
        echo "---[INFO]: Config-type: ${NIC_TYPE}"
        echo "---[INFO]: Config-ifname: ${NIC_NAME}"
        echo "---[INFO]: Config-fullpath: ${SYSTEMCONNECTIONS_DIR}/${NEWCONFIG}"
        echo "---[NOTE]: DHCP is automatically set to ${AUTO}..."
        echo "---[NOTE]: Should you need to configure a static IP, you can do so by running this script again."
        echo -e "\r"
        read -p "Press any key to continue..."
        echo -e "\r"
        
        # Show the SSID list
        showSSID

        # Get WiFi credentials
        local ssid=$(getValidInput "${INPUT_SSID}" validateSSID)
        local passphrase=$(getValidInput "${INPUT_PASSPHRASE}" validatePassphrase)
        
        # Create the new WiFi connection using nmcli
        sudo nmcli connection add type ${NIC_TYPE} con-name ${NEWCONFIG} ifname ${NIC_NAME} \
            ssid "${ssid}" \
            wifi-sec.key-mgmt wpa-psk \
            wifi-sec.psk "${passphrase}" \
            ipv4.method ${AUTO} \
            ipv6.method ${AUTO}

        # Set the flag to indicate the new config file is created
        newConfigFileIsCreated=true
        networkConfigIsChanged=true
    else
        # If current config matches new config, no action needed
        if [[ "${currConfig}" == "${NEWCONFIG}" ]]; then
            echo "---[INFO]: Configuration file already exists"
        else
            echo "---[STATUS]: Renaming existing configuration from '${currConfig}' to '${NEWCONFIG}'..."
            sudo nmcli connection modify "${currConfig}" connection.id "${NEWCONFIG}"

            sleep 1

            echo "---[STATUS]: Moving existing configuration file from '${currConfig}.nmconnection' to '${NEWCONFIGNAME}'..."
            sudo mv "${SYSTEMCONNECTIONS_DIR}/${currConfig}.nmconnection" \
                "${SYSTEMCONNECTIONS_DIR}/${NEWCONFIGNAME}"
            
            sleep 1

            echo "---[STATUS]: Ensuring the new file has the correct permissions: 600"
            sudo chmod 600 "${SYSTEMCONNECTIONS_DIR}/${NEWCONFIGNAME}"

            sleep 1
            sudo nmcli connection reload "${NEWCONFIG}"

            networkConfigIsChanged=true
        fi
    fi

    # Show the current Nmcli Connection Info
    showCurrentNmcliConfig

    if [[ "${newConfigFileIsCreated}" == false ]]; then
        echo -e "\r"
        while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
            read -e -p "Connect to a different SSID? (y/n): " answer
            if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
                break
            fi
        done

        if [[ "${answer,,}" == "y" ]]; then
            currConfig=""

            cleanUpExistingConfig
            writeNmcliConfigToFile

            return 0
        fi
    fi
}

changeNetworkConfig() {
    local configFile="${SYSTEMCONNECTIONS_DIR}/${NEWCONFIGNAME}"

    if [[ ! -f "${configFile}" ]]; then
        echo -e "\r"
        echo "***[ERROR]: Configuration file *NOT* found: ${configFile}"
        echo -e "\r"
        exit 1
    fi

    # Extract the method line under the [ipv4] section
    local methodLine=$(awk '/^\[ipv4\]/ {found=1} found && /^method=/ {print $0; exit}' "${configFile}")
    local methodValue=$(echo ${methodLine} | cut -d"=" -f2)

    if [[ "${newConfigFileIsCreated}" == false ]]; then
        if [[ -n "${methodValue}" ]]; then
            echo -e "\r"
            echo "---[INFO]: DHCP is CURRENTLY set to: ${methodValue}"
        else
            echo -e "\r"
            echo "***[ERROR]: Unable to find the 'method' line under the [ipv4] section in ${configFile}"
            echo -e "\r"
            exit 1
        fi

        echo -e "\r"
        if [[ "${methodValue}" == "${AUTO}" ]]; then
            handleMethodAuto
        else
            handleMethodManual
        fi
    fi

    # Reload and restart the connection
    if [[ "${networkConfigIsChanged}" == true ]]; then
        echo "---[STATUS]: Reloading and restarting the connection... Please wait..."
        sudo nmcli connection reload "${NEWCONFIG}"
        if [[ $? -ne 0 && $? -ne 100 ]]; then
            echo "***[ERROR]: Failed to reload the connection"
            sleep 2
            exit 1
        fi
        sudo nmcli connection up "${NEWCONFIG}"
        if [[ $? -ne 0 ]]; then
            echo "***[ERROR]: Failed to bring up the connection"
            sleep 2
            exit 1
        fi
    fi

    # Show the current Nmcli Connection Info
    showCurrentNmcliConfig

    # Show the WiFi info
    showWifiInfo

    # Show the network info
    showNetworkInfo

    # Reboot the system
    if [[ "${networkConfigIsChanged}" == true ]]; then
        rebootDevice
    else
        read -p "Press any key to continue..."
    fi
}

handleMethodAuto() {
    local answer=""
    while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
        read -e -p "Configure STATIC-IP? (y/n): " answer
        if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
            echo -e "\r"    
            echo "***[ERROR]: Please enter y, Y, n, or N only."
            echo -e "\r"
        fi
    done
    
    if [[ "${answer,,}" == "y" ]]; then
        changeNetworkConfigToStaticIp
        networkConfigIsChanged=true
    else
        echo -e "\r"
        echo "---[INFO]: Network configuration was left unchanged (DHCP)."
        echo -e "\r"
    fi
}

handleMethodManual() {
    local answer=""
    while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
        read -e -p "Configure a *NEW* STATIC-IP? (y/n): " answer
        if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
            echo -e "\r"    
            echo "***[ERROR]: Please enter y, Y, n, or N only."
            echo -e "\r"
        fi
    done
    
    if [[ "${answer,,}" == "y" ]]; then
        changeNetworkConfigToStaticIp
        networkConfigIsChanged=true
    else
        local dhcp_answer=""
        while [[ ! "${dhcp_answer,,}" =~ ^[yn]$ ]]; do
            read -e -p "Configure DHCP instead? (y/n): " dhcp_answer
            if [[ ! "${dhcp_answer,,}" =~ ^[yn]$ ]]; then
                echo -e "\r"    
                echo "***[ERROR]: Please enter y, Y, n, or N only."
                echo -e "\r"
            fi
        done
        
        if [[ "${dhcp_answer,,}" == "y" ]]; then
            changeNetworkConfigToDhcp
            networkConfigIsChanged=true
        else
            echo -e "\r"
            echo "---[INFO]: Network configuration was left unchanged (STATIC-IP)."
            echo -e "\r"
        fi
    fi
}

changeNetworkConfigToDhcp() {
    echo -e "\r"
    echo "---[STATUS]: Changing network configuration to *DHCP*..."
    
    # First set method to auto (DHCP)
    sudo nmcli connection modify "${NEWCONFIG}" ipv4.method "${AUTO}"
    
    # Then remove all existing IPv4 settings
    sudo nmcli connection modify "${NEWCONFIG}" \
        ipv4.addresses "" \
        ipv4.gateway "" \
        ipv4.dns "" \
        ipv4.route-metric ""
    
    echo -e "\r"
    echo "---[INFO]: Network configuration changed to *DHCP* successfully"
    echo -e "\r"
    
    networkConfigIsChanged=true
}

changeNetworkConfigToStaticIp() {
    echo -e "\r"
    echo "---[STATUS]: Changing network configuration to *STATIC-IP*..."
    
    # Get and validate user input
    local static_ips=()
    local gateway=""
    local dns=""
    local metric=""
    
    # Get multiple static IPs
    echo "---[INFO]: You can add multiple IP addresses. Enter 'done' when finished."
    while true; do
        read -e -p "${INPUT_STATIC_IP} ('${DONE}' to finish): " ip_input
        
        if [[ "${ip_input}" == "${DONE}" ]]; then
            if [[ ${#static_ips[@]} -eq 0 ]]; then
                echo "***[ERROR]: At least one IP address is required"
                continue
            fi
            break
        fi
        
        if validateIpAddress "${ip_input}"; then
            echo "---[STATUS]: Checking if ${ip_input} is in use on this system..."
            if validateIpAddressInUse "${ip_input}"; then
                echo "---[UPDATE]: IP address ${ip_input} is available and can be used"
                static_ips+=("${ip_input}")
            fi
        fi
    done
    
    # Get gateway and validate it's in the same subnet as the first IP
    while true; do
        gateway=$(getValidInput "${INPUT_GATEWAY}" validateSimpleIpAddress)
        if validateGatewayInSubnet "${static_ips[0]}" "${gateway}"; then
            echo "---[STATUS]: Gateway ${gateway} is in the same subnet as ${static_ips[0]}"
            break
        fi
    done
    
    # Get DNS
    dns=$(getValidInput "${INPUT_DNS}" validateSimpleIpAddress)
    
    # Get metric and validate it's not in use
    while true; do
        metric=$(getValidInput "${INPUT_METRIC}" validateNumeric)
        if validateMetricInUse "${metric}"; then
            break
        fi
    done
    
    # Join all IP addresses with commas for nmcli
    local ip_addresses=$(IFS=","; echo "${static_ips[*]}")
    
    # Modify the connection with static IP settings
    sudo nmcli connection modify "${NEWCONFIG}" \
        ipv4.method "${MANUAL}" \
        ipv4.addresses "${ip_addresses}" \
        ipv4.gateway "${gateway}" \
        ipv4.dns "${dns}" \
        ipv4.route-metric "${metric}"
    
    echo -e "\r"
    echo "---[INFO]: Network configuration changed to *STATIC-IP* successfully"
    echo "---[INFO]: Configured IP addresses: ${ip_addresses}"
    echo -e "\r"
}

rebootDevice() {
    echo -e "\r"
    echo "---[INFO]: For the changes to take effect, please reboot the device."
    echo "---[NOTE]: If the device becomes inaccessible after reboot, a physical power cycle (turn off and on) may resolve the issue."
    echo -e "\r"
    
    local answer=""
    while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
        read -e -p "Reboot now? (y/n): " answer
        if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
            echo -e "\r"    
            echo "***[ERROR]: Please enter y or n only."
            echo -e "\r"
        fi
    done
    
    if [[ "${answer,,}" == "y" ]]; then
        echo -e "\r"
        echo "---[STATUS]: System will reboot now..."
        echo -e "\r"
        sleep 2
        sudo reboot
    else    
        echo -e "\r"
        echo "---[REMINDER]: Please reboot manually later for changes to take effect."
        echo -e "\r"
    fi
}


#---MAIN FUNCTION
main() {
    checkIfRootOrSudoer

    disableStopUserConfigService

    disablePowerSavingMode

	retrieveNmcliConfigName

    writeNmcliConfigToFile

    changeNetworkConfig
}

#---EXEC MAIN
main
