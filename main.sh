#!/bin/bash

# Retrieve the current directory of the script
REPO_DIR=$(dirname "$(realpath "$0")")


# COLOR CONSTANTS
FG_GREY='\e[90m'
FG_RED='\e[31m'
RESET='\e[0m'


# CONSTANTS
LAN_NIC_NAME="eth0"  # Default LAN interface
WIFI_NIC_NAME="wlan0"  # Default WiFi interface


# VARIABLES
ethernetIsAvailable=false
wifiIsAvailable=false


# Check if running as root or with sudo
if [[ "${EUID}" -ne 0 ]]; then
    echo -e "\r"
    echo "***[DENIED]: This script must be run as root or with sudo."
    echo -e "\r"
    exit 1
fi

# Handle Ctrl+C in main script
trap 'echo -e "\r\n\r\n---[STATUS]: Exiting Network Configuration Tool.\r\n"; exit 0' SIGINT

# Function to display the menu
display_menu() {
    clear
    echo -e "\r"
    echo "----------------------------------------"
    echo "        Network Configuration           "
    echo "----------------------------------------"
    if ip a | grep -q "${LAN_NIC_NAME}"; then
        echo "1. Ethernet"

        ethernetIsAvailable=true
    else
        echo -e "${FG_GREY}1. Ethernet (${FG_RED}Not ${FG_GREY}Available)${RESET}"
    fi
    if ip a | grep -q "${WIFI_NIC_NAME}"; then
        echo "2. WiFi"

        wifiIsAvailable=true
    else
        echo -e "${FG_GREY}2. Wifi (${FG_RED}Not ${FG_GREY}Available)${RESET}"
    fi
    echo "----------------------------------------"
    echo "q. Quit"
    echo -e "\r"
}

# Main loop
while true; do
    # Display the menu
    display_menu
    
    # Read user input
    read -e -p "Enter your choice (1, 2, or q): " choice
    
    # Process the user's choice
    case "${choice}" in
        1)
            if [[ "${ethernetIsAvailable}" == false ]]; then
                echo -e "\r"
                echo "***[ERROR]: Ethernet is not available on this system."
                echo -e "\r"
                sleep 1
                continue
            fi
        
            echo -e "\r"
            echo "---[STATUS]: Starting Ethernet Configuration..."
            sleep 1

            ${REPO_DIR}/scripts/ethernet_config.sh

            echo -e "\r"
            ;;
        2)
            if [[ "${wifiIsAvailable}" == false ]]; then
                echo -e "\r"
                echo "***[ERROR]: WiFi is not available on this system."
                echo -e "\r"
                sleep 1
                continue
            fi

            echo -e "\r"
            echo "---[STATUS]: Starting WiFi Configuration..."
            sleep 1

            ${REPO_DIR}/scripts/wifi_config.sh

            echo -e "\r"
            ;;
        q|Q)
            echo -e "\r"
            echo "---[STATUS]: Exiting Network Configuration Tool."
            echo -e "\r"
            exit 0
            ;;
        *)
            echo -e "\r"
            echo "***[ERROR]: Invalid option. Please enter 1, 2, or q."
            echo -e "\r"
            sleep 1
            ;;
    esac
done
