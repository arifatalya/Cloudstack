---
title: Apache CloudStack Installation on Ubuntu 24.04 (Noble Numbat)

---

# Apache CloudStack Installation on Ubuntu 24.04 (Noble Numbat)

**CloudStack 19:**
* 2206059383 - Aisyah Arifatul Alya
* 2206814324 - Fairuz Muhammad
* 2206810452 - Mario Matthews Gunawan
* 2206826835 - Ryan Safa Tjendana
---

## I. System Update and Tools Installation
> All the commands below SHALL be ran under the root privilege.
```bash!
sudo -i
apt update && apt upgrade -y
apt install htop lynx duf vim tar -y
apt install bridge-utils
apt install intel-microcode
apt install openntpd openssh-server 
```
- **htop:** Interactive system monitor to view running processes and resource usage.
- **lynx:** Text-based web browser for browsing websites from the terminal.
- **duf:** Disk usage utility that displays mounted filesystems and their usage.
- **vim:** Text editor used to create and edit files in the terminal.
- **tar:** Tool to compress and extract archive files.
- **bridge-utils:** Provides tools to create and manage network bridges.
- **intel-microcode:** Installs CPU microcode updates for Intel processors.
- **openntpd:** Daemon to synchronize the system clock with internet time servers.
- **openssh-server:** SSH server to allow remote connections to the machine.

## II. Modify the Network Configuration File
1. Redirect to the netplan directory.
```bash
cd /etc/netplan
```
2. Using the ***ls*** command, check whether is there any .yaml file within the directory.
3. Within the directory, do this command to edit the .yaml file.

```bash
sudo vim 50-cloud-init.yaml
```
4. Using the vim editor, enter the visual line mode by clicking on ***'Shift + v'***. Because we will change the entire content of the file, click ***'Enter'*** to block each line one by one, then click the ***'d'*** key to delete everything. After making sure that the file is empty, copy the configuration below by entering the insert mode first by clicking ***'i'***. For the "addresses:" line below the "cloudbr0:", the address could differ depending on the machine, so consider checking it first with the ***ip route*** and ***ifconfig*** command.
```yaml=
network:
  version: 2
  renderer: networkd
  ethernets:
    wlp0s20f3:
      dhcp4: false
      dhcp6: false
      optional: true
  bridges:
    cloudbr0:
      addresses: [192.168.1.77/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [1.1.1.1,8.8.8.8]
      interfaces: [wlp0s20f3]
      dhcp4: false
      dhcp6: false
      parameters:
        stp: false
        forward-delay: 0
```

![image](https://hackmd.io/_uploads/HkEUyzLxee.png)
5. Click the escape key and finally type on ":wq" to write and quit the editor. 
6. Apply changes to the file by using these commands below:
```bash
sudo netplan generate
sudo netplan apply
reboot
# Or if you're not sure, yet:
sudo netplan try
```

## III. Configure LVM

```bash
sudo vgextend ubuntu-vg /dev/sda
sudo vgextend ubuntu-vg /dev/sdb
sudo lvextend -L +100G /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/ubuntu-vg/ubuntu-lv
```

## IV. Enable SSH Root Login

> This is done by uncommenting the "PermitRootLogin yes" line.
```bash
vim /etc/ssh/sshd_config
#PermitRootLogin yes (uncomment this line)
service ssh restart
# Or
systemctl restart sshd.service
```

## V. CloudStack Management Server Installation

### 5.1. Setting up the environment for the CloudStack infrastructure installation and setup.
```bash
sudo -i
mkdir -p /etc/apt/keyrings
wget -O- http://packages.shapeblue.com/release.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/cloudstack.gpg > /dev/null

echo deb [signed-by=/etc/apt/keyrings/cloudstack.gpg] http://packages.shapeblue.com/cloudstack/upstream/debian/4.17 / > /etc/apt/sources.list.d/cloudstack.list
```

### 5.2. Installing CloudStack Management Server and MySQL Server
```bash
apt install cloudstack-management mysql-server
```

### 5.3. Configuring MySQL database

```bash
vim /etc/mysql/mysql.conf.d/mysqld.cnf

[mysqld]
server-id = 1
sql-mode="STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION,ERROR_FOR_DIVISION_BY_ZERO,NO_ZERO_DATE,NO_ZERO_IN_DATE,NO_ENGINE_SUBSTITUTION"
innodb_rollback_on_timeout=1
innodb_lock_wait_timeout=600
max_connections=1000
log-bin=mysql-bin
binlog-format = 'ROW'
```
```bash
systemctl restart mysql
systemctl status mysql
```

### 5.4. Deploying database as root and creating new user
```bash
cloudstack-setup-databases cloud:cloud@localhost --deploy-as=root:[insert your root password] -i 192.168.1.77
```

## VI. Setting up NFS server
### 6.1. Installing the packages for NFS server
```bash
sudo -i
apt install nfs-kernel-server quota
```

```bash
echo "/export  *(rw,async,no_root_squash,no_subtree_check)" > /etc/exports
mkdir -p /export/primary /export/secondary
exportfs -a
```
### 6.2. Configuring NFS server
```bash
sed -i -e 's/^RPCMOUNTDOPTS="--manage-gids"$/RPCMOUNTDOPTS="-p 892 --manage-gids"/g' /etc/default/nfs-kernel-server
sed -i -e 's/^STATDOPTS=$/STATDOPTS="--port 662 --outgoing-port 2020"/g' /etc/default/nfs-common
echo "NEED_STATD=yes" >> /etc/default/nfs-common
sed -i -e 's/^RPCRQUOTADOPTS=$/RPCRQUOTADOPTS="-p 875"/g' /etc/default/quota
```
```bash
service nfs-kernel-server restart
```

## VII. Configuring CloudStack Host with KVM
### 7.1. Install KVM and CloudStack Agent
```bash
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloudstack-agent
```


### 7.2. Enable KVM Modules
```bash
lsmod | grep kvm
```
```bash!
# Do this if not loaded
sudo modprobe kvm
sudo modprobe kvm_intel
```

### 7.3. Configure libvirt for TCP

- Editing `/etc/libvirt/qemu.conf`
```bash!
vim /etc/libvirt/qemu.conf
```
```ini!
vnc_listen = "0.0.0.0"
```

- Editing `/etc/libvirt/libvirtd.conf` by adding this at the bottom of the file.
```bash!
vim /etc/libvirt/libvirtd.conf
```

```ini!
listen_tls = 0
listen_tcp = 1
tcp_port = "16509"
mdns_adv = 0
auth_tcp = "none"
```

- Enabling libvirtd for TCP listening 
```bash
vim /etc/default/libvirtd
```
```ini
LIBVIRTD_ARGS="--listen"
```

### 7.4. Masking unused sockets and restarting libvirtd

```bash
sudo systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket libvirtd-tls.socket libvirtd-tcp.socket
```
```bash
sudo systemctl restart libvirtd
sudo systemctl status libvirtd
```

### 7.5. Disable AppArmor for libvirt
```bash
sudo ln -s /etc/apparmor.d/usr.sbin.libvirtd /etc/apparmor.d/disable/
sudo ln -s /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd
sudo apparmor_parser -R /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper
```

## VIII. Generate Unique Host ID
```bash
sudo apt install -y uuid-runtime
UUID=$(uuidgen)
echo "host_uuid = \"$UUID\"" | sudo tee -a /etc/libvirt/libvirtd.conf
sudo systemctl restart libvirtd
```

## IX. Configure Iptables Firewall
```bash!
NETWORK=192.168.XXX.XXX/24
iptables -A INPUT -s $NETWORK -m state --state NEW -p udp --dport 111 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 111 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 2049 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 32803 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p udp --dport 32769 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 892 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 875 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 662 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 8250 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 8080 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 8443 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 9090 -j ACCEPT
iptables -A INPUT -s $NETWORK -m state --state NEW -p tcp --dport 16514 -j ACCEPT

sudo apt install iptables-persistent
```

## X. Launch CloudStack Management Server

```bash!
cloudstack-setup-management
systemctl status cloudstack-management
```
```bash!
# (Optional) Live monitoring of logs:
tail -f /var/log/cloudstack/management/management-server.log
```
> Access via browser with: 
`http://<YOUR_IP>:8080`
