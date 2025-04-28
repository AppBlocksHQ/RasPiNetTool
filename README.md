# awesome-raspberrypi-networkconfig
This repository includes scripts to configure the eth0 (Ethernet) and wlan0 (Wi-Fi) interfaces, using iwd as a modern alternative to wpa_supplicant for wireless network management.

***

## Powersupply
Ensure your Raspberry Pi receives adequate power to prevent issues such as network instability or unexpected reboots. The power requirements and connectors differ between models:​
For example:
- Raspberry Pi 3: Utilizes a micro-USB connector and requires a power supply of 5.1V / 2.5A.​
- Raspberry Pi 4: Utilizes a USB-C connector and requires a power supply of 5.1V / 3.0A.​

Using a power supply that does not meet these specifications can lead to performance problems. For detailed hardware information and power requirements, refer to the official Raspberry Pi documentation: 
```
https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
```

***

## USB-to-UART
For the ones who want to enable serial communication via USB-to-UART on your Raspberry Pi, add the following lines to the [all] section of the config.txt file:
```
[all]
enable_uart=1
dtoverlay=disable-bt
```
This configuration activates the UART interface and disables Bluetooth, freeing up the serial port for communication. After making these changes, reboot your Raspberry Pi to apply them.

***

## Initial Setup
#### Connect to the Raspberry-Pi
Using your favorite terminal, connect to the Raspberry-Pi via `serial` or `ssh`.

#### Disable & Stop userconfig.service
```shell
sudo systemctl disable userconfig.service
sudo systemctl stop userconfig.service
```

#### Create __ssh__ `public` and `private` keys
Generate private and public keys for your user-account:
```shell
ssh-keygen
```

#### (Optional) Permit `root` SSH
```shell
sudo -S <<< "tibbo" sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Extract the public key:
```shell
cat ~/.ssh/id_rsa.pub
```
NOTE: you will need to add the content of public key __id_rsa.pub__ to the `SSH Keys` of your `Github account`.

#### Update & Upgrade
```shell
sudo apt update -y
sudo apt upgrade -y
```
NOTE: The duration of the upgrade process on a Raspberry Pi can vary significantly depending on the model, the number of packages to be updated, and the speed of your internet connection.

#### Install apps
```shell
sudo apt install -y git
```

***

## Clone Repo
#### Create `repo` directory
```shell
sudo mkdir /repo
sudo chown $USER:$USER -R /repo
```

#### Clone repo `awesome-raspberrypi-networkconfig`
```shell
cd /repo
git clone git@github.com:imcase/awesome-raspberrypi-networkconfig.git
```

***

## Configure Network
#### Configure Ethernet eth0
```shell
cd /repo/awesome-raspberrypi-networkconfig
sudo ./main.sh
```

***
