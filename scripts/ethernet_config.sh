#!/bin/bash -m

# Handle Ctrl+C gracefully
trap 'echo -e "\r\nEthernet configuration canceled. Returning to main menu...\r\n"; exit 0' SIGINT

#---CONSTANTS
AUTO="auto"
MANUAL="manual"
NIC_TYPE="ethernet"
NIC_NAME="eth0"
METRIC_VAL="10"
NEWCONFIG="eth0-persistent"
NEWCONFIGNAME="${NEWCONFIG}.nmconnection"
SYSTEMCONNECTIONS_DIR="/etc/NetworkManager/system-connections"

INPUT_STATIC_IP="Enter STATIC-IP (e.g., 192.168.1.100/24)"
INPUT_GATEWAY="Enter Gateway IP (e.g., 192.168.1.1)"
INPUT_DNS="Enter DNS IP (e.g., 8.8.8.8)"
INPUT_METRIC="Enter Metric value"

#---VARIABLES
currConfig=""
newConfigFileIsCreated=false
networkConfigIsChanged=false

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

retrieveNmcliConfigName() {
    echo "---[STATUS]: retrieving the current Nmcli Ethernet Configuration..."

    # Get the result from nmcli and filter by nicName
    local result=$(nmcli connection show | grep "${NIC_NAME}")

    # Extract the NAME column (everything before the UUID)
    currConfig=$(echo "${result}" | sed -E 's/[[:space:]]{2,}/ /g' | awk '{$NF=""; $(NF-1)=""; $(NF-2)=""; sub(/[[:space:]]+$/, ""); print}')

    echo "---[FOUND]: ...${currConfig}" 
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

showNetworkInfo() {
    echo -e "\r"
    echo "---------------------------------------------------------------------"
    echo "    Network Info for ${NIC_NAME}"
    echo "---------------------------------------------------------------------"
    ifconfig ${NIC_NAME}
    echo "---------------------------------------------------------------------"
    echo -e "\r"
}

rebootDevice() {
    echo -e "\r"
    echo "---[INFO]: For the changes to take effect, please reboot the device."
    echo "---[NOTE]: If the device becomes inaccessible after reboot, a physical power cycle (turn off and on) may be necessary."
    echo -e "\r"

    local answer=""
    while [[ ! "${answer,,}" =~ ^[yn]$ ]]; do
        read -e -p "Reboot now? (y/n): " answer
        if [[ ! "${answer,,}" =~ ^[yn]$ ]]; then
            echo -e "\r"    
            echo "***[ERROR]: Please enter y, Y, n, or N only."
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
        echo "---[INFO]: Please reboot manually later for changes to take effect."
        echo -e "\r"
    fi
}

writeNmcliConfigToFile() {
    echo "---[STATUS]: Checking if Nmcli Ethernet Configuration ${currConfig} already exists..."

    if [[ -z "${currConfig}" ]]; then
        echo "---[INFO]: No Nmcli Ethernet Configuration found for ${NIC_NAME}."
        echo "---[STATUS]: Creating new Nmcli Ethernet Configuration for ${NIC_NAME} called ${NEWCONFIG}..."
        sudo nmcli connection add type ${NIC_TYPE} con-name ${NEWCONFIG} ifname ${NIC_NAME} ipv4.method ${AUTO} ipv6.method ${AUTO}

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

            echo "---[STATUS]: Moving existing configuration file from '${currConfig}.nmconnection' to '${NEWCONFIG}.nmconnection'..."
            sudo mv "${SYSTEMCONNECTIONS_DIR}/${currConfig}.nmconnection" \
                "${SYSTEMCONNECTIONS_DIR}/${NEWCONFIG}.nmconnection"
            
            sleep 1

            echo "---[STATUS]: Ensuring the new file has the correct permissions: 600"
            sudo chmod 600 "${SYSTEMCONNECTIONS_DIR}/${NEWCONFIG}.nmconnection"

            sleep 1
            echo "---[STATUS]: Reloading and restarting the connection... Please wait..."
            sudo nmcli connection reload "${NEWCONFIG}"
            sudo nmcli connection up "${NEWCONFIG}"
            
            networkConfigIsChanged=true
        fi
    fi

    showCurrentNmcliConfig
}

validateIpAddressInUse() {
    local ip=${1}
    local ip_part=${ip%/*}
    
    # Check if IP is already in use
    if ip a | grep -q "inet ${ip_part}/"; then
        echo "***[ERROR]: IP address ${ip_part} is already in use on this system" >&2
        return 1
    fi
    return 0
}

validateMetricInUse() {
    local metric=${1}
    
    # Check if metric is already in use
    if ip route show default | grep -q "metric ${metric}"; then
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

changeNetworkConfig() {
    local configFile="/etc/NetworkManager/system-connections/${NEWCONFIGNAME}"

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
        sudo nmcli connection up "${NEWCONFIG}"
    fi

    # Show the current Nmcli Connection Info
    showCurrentNmcliConfig

    # Show the network info
    showNetworkInfo

    # Reboot the system
    if [[ "${networkConfigIsChanged}" == true ]]; then
        rebootDevice
    else
        read -p "Press any key to continue..."
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
    local static_ip=""
    local gateway=""
    local dns=""
    local metric=""
    
    # Get static IP and validate it's not in use
    while true; do
        static_ip=$(getValidInput "${INPUT_STATIC_IP}" validateIpAddress)

        echo "---[STATUS]: Checking if ${static_ip} is not in use on this system..."

        if validateIpAddressInUse "${static_ip}"; then
            echo "---[STATUS]: IP address ${static_ip} is available and can be used"
            break
        fi
    done
    
    # Get gateway and validate it's in the same subnet
    while true; do
        gateway=$(getValidInput "${INPUT_GATEWAY}" validateSimpleIpAddress)
        if validateGatewayInSubnet "${static_ip}" "${gateway}"; then
            echo "---[STATUS]: Gateway ${gateway} is in the same subnet as ${static_ip}"
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
    
    # Modify the connection with static IP settings
    sudo nmcli connection modify "${NEWCONFIG}" \
        ipv4.method "${MANUAL}" \
        ipv4.addresses "${static_ip}" \
        ipv4.gateway "${gateway}" \
        ipv4.dns "${dns}" \
        ipv4.route-metric "${metric}"
    
    echo -e "\r"
    echo "---[INFO]: Network configuration changed to *STATIC-IP* successfully"
    echo -e "\r"
}


#---MAIN FUNCTION
main() {
    checkIfRootOrSudoer

    disableStopUserConfigService

	retrieveNmcliConfigName

    writeNmcliConfigToFile

    changeNetworkConfig
}

#---EXEC MAIN
main
