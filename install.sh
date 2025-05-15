#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  sleep 15
  exit
fi

UBUNTU_VERSION=$(lsb_release -rs)
REQUIRED_VERSION1="22."
REQUIRED_VERSION2="20."

if (( $(echo "$UBUNTU_VERSION < $REQUIRED_VERSION1" | bc -l) )) && [[ "$UBUNTU_VERSION" != $REQUIRED_VERSION2* ]]; then
    sleep 15
    exit
fi

apt update && apt upgrade -y

GATEWAY=$(ip r | awk '/default/ {print $3}')
IP=$(ip r | awk '/src/ {print $9}')
ADAPTER=$(ip link | awk -F: '$0 !~ "lo|vir|wl|^[^0-9]"{print $2;getline}')

HOSTS_CONTENT="127.0.0.1\tlocalhost\n$IP\admin.kelompok19.xyz\tkelompok19"
apt install bridge-utils

if ! brctl show | grep -q 'br0'; then
    brctl addbr br0
fi

# Check if the interface is already added to the bridge
if ! brctl show br0 | grep -q "$ADAPTER"; then
    brctl addif br0 "$ADAPTER"
fi

NETPLAN_CONTENT="network:
    version: 2
    renderer: networkd
    ethernets:
        $ADAPTER:
            dhcp4: no
            dhcp6: no
    bridges:
        br0:
            interfaces: [$ADAPTER]
            dhcp4: no
            dhcp6: no
            addresses: [$IP/24]
            gateway4: $GATEWAY
            nameservers:
                addresses: [8.8.8.8, 8.8.4.4]"

CURRENT_GATEWAY=$(grep -oP '(?<=gateway4: )[^ ]*' /etc/netplan/01-network-manager-all.yaml)

if ! grep -Fxq "$HOSTS_CONTENT" /etc/hosts
then
    echo -e "$HOSTS_CONTENT" | sudo tee /etc/hosts
fi

if [ "$CURRENT_GATEWAY" != "$GATEWAY" ]
then
    cp /etc/netplan/01-network-manager-all.yaml /etc/netplan/01-network-manager-all.yaml.bak
    echo "$NETPLAN_CONTENT" | sudo tee /etc/netplan/01-network-manager-all.yaml
fi

netplan apply
systemctl restart NetworkManager
hostnamectl set-hostname admin.kelompok19.xyz

apt-get install -y openntpd openssh-server sudo vim htop tar intel-microcode bridge-utils mysql-server

UBUNTU_VERSION=$(lsb_release -rs)

if [[ "$UBUNTU_VERSION" == "20."* ]]
then
    echo deb [arch=amd64] http://download.cloudstack.org/ubuntu focal 4.18  > /etc/apt/sources.list.d/cloudstack.list
elif [[ "$UBUNTU_VERSION" == "22."* ]]
then
    echo deb [arch=amd64] http://download.cloudstack.org/ubuntu jammy 4.18  > /etc/apt/sources.list.d/cloudstack.list
else
    echo "Unsupported Ubuntu version. This script supports Ubuntu 20.xx and 22.xx only."
    exit 1
fi


wget -O - http://download.cloudstack.org/release.asc|gpg --dearmor > cloudstack-archive-keyring.gpg


mv cloudstack-archive-keyring.gpg /etc/apt/trusted.gpg.d/


apt update && apt upgrade -y
apt-get install -y cloudstack-management cloudstack-usage

cat <<EOF | sudo tee /etc/mysql/mysql.conf.d/cloudstack.cnf
[mysqld]
server_id = 1
sql-mode='STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,ERROR_FOR_DIVISION_BY_ZERO,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_ENGINE_SUBSTITUTION'
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=1000
log-bin=mysql-bin
binlog-format = 'ROW'
EOF

systemctl restart mysql

sudo mysql <<EOF
SELECT user, authentication_string, plugin, host FROM mysql.user;
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'kelompok19admin';
UPDATE mysql.user SET plugin='mysql_native_password' WHERE User='root';
FLUSH PRIVILEGES;
EOF

apt-get install -y cloudstack-management cloudstack-usage
cloudstack-setup-databases admin:admin@localhost --deploy-as=root:kelompok19admin

cloudstack-setup-management

ufw allow mysql
mkdir -p /export/primary
mkdir -p /export/secondary
echo "/export *(rw,async,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports
exportfs -a
apt install nfs-kernel-server -y
service nfs-kernel-server restart
mkdir -p /mnt/primary
mkdir -p /mnt/secondary
mount -t nfs localhost:/export/primary /mnt/primary
mount -t nfs localhost:/export/secondary /mnt/secondary

width=$(tput cols)
progress_width=$((width - 20))
sleep_duration=$(echo "60 / $progress_width" | bc -l)
echo -n "Progress: ["
for i in $(seq 1 $progress_width)
do
    sleep $sleep_duration
    echo -n "#"
done
echo "]"
