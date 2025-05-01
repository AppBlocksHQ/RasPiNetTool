#!/bin/bash

# Retrieve the current directory of the script
REPO_DIR=$(dirname "$(realpath "$0")")

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
    echo "1. Ethernet"
    echo "2. WiFi"
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
            echo -e "\r"
            echo "---[STATUS]: Starting Ethernet Configuration..."
            sleep 1

            ${REPO_DIR}/scripts/ethernet_config.sh

            echo -e "\r"
            ;;
        2)
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
