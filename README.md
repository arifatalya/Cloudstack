# Apache CloudStack Installation on Ubuntu 24.04 (Noble Numbat)

**CloudStack 19:**
* 2206059383 - Aisyah Arifatul Alya
* 2206814324 - Fairuz Muhammad
* 2206810452 - Mario Matthews Gunawan
* 2206826835 - Ryan Safa Tjendana
---

## I. System Update and Tools Installation

### Prerequisites
Before starting:
- Ensure the system has at least:
    - 2 CPUs, 4 GB RAM (Management Server only)
    - 1 Ethernet or bridged Wi-Fi (test-only)
    - 100 GB storage (expandable via LVM)
- Use Ubuntu 24.04 Server, fresh install.
- Set hostname properly:
`hostnamectl set-hostname cloudstack-node`

### Installation
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

> Ensure time is synced properly to avoid certificate/agent failures:
```
systemctl enable openntpd
systemctl start openntpd
ntpdate -u pool.ntp.org
```


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

>  Warning: CloudStack is designed to use bridged Ethernet (eth0). Using Wi-Fi (wlp0s20f3) as part of cloudbr0 may result in VM communication issues. This is acceptable only for testing, not production.

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

> By default, MySQL on Ubuntu 24.04 uses "auth_socket" for root authentication.
This means logging in to MySQL with mysql -u root -p will fail unless you’ve explicitly assigned a password to the root account and changed its authentication method.

To allow root login with a password (needed for CloudStack database deployment):
```
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'yourpassword';
FLUSH PRIVILEGES;
```

>Replace 'yourpassword' with a secure password.
After this, the root account will support password-based login and work with cloudstack-setup-databases.

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

### 7.6. Agent Troubleshooting
If agent fails to start, verify:
- File: /etc/cloudstack/agent/agent.properties
- Log: /var/log/cloudstack/agent/agent.log
- Common fixes:
    - Failed to get private nic name → set private.network.device properly
    - Unable to start agent → ensure libvirtd is up and TCP is enabled

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

`http://<YOUR_IP>:8080/client`

- Default credentials:
    - Username: admin
    - Password: password

### Manual Certificate Setup (If Agent Fails to Connect).
> If agent fails with bad_certificate or SSL handshake failed, re-run agent setup:

`cloudstack-setup-agent --configure`
>Ensure /etc/cloudstack/agent/agent.properties has:
```
private.network.device=wlp0s20f3
public.network.device=cloudbr0
guest.network.device=cloudbr0
```

## XI. Prepare User-Data with Cloud-Init
> This step is crucial if you're using Ubuntu Cloud Image as the instance template. Since it doesn't include a default password, you won’t be able to access the VM without setting up credentials and basic configuration through cloud-init.
- Install cloud-init:
```bash!
 sudo apt install cloud-init
```
- Make this somewhere on your management server:
```bash!
## Example:
mkdir -p cloudstack/cloud-init/
vim cloudstack/cloud-init/cloud-init.yaml
```
```yaml!
#cloud-config
hostname: kelompok19-vm
manage_etc_hosts: true

users:
  - name: ubuntu
    ssh-authorized-keys:
      - ssh-rsa AAAAB3... # your public key
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    shell: /bin/bash

chpasswd:
  list: |
    ubuntu:kelompok19admin
  expire: false

ssh_pwauth: true

runcmd:
  - echo "nameserver 8.8.8.8" > /etc/resolv.conf
```
- Encode the YAML file:
```bash!
base64 -w 0 cloud-init.yaml > cloud-init.b64
```
- Show the .b64 file on your terminal or open it with file editor:
```bash!
cat cloud-init.b64
## or
vim cloud-init.yaml
```
```ini!
## Example:
kelompok19@kelompok19server:~/cloudstack/cloud-init$ cat cloud-init.b64
I2Nsb3VkLWNvbmZpZwpob3N0bmFtZToga2Vsb21wb2sxOS12bQptYW5hZ2VfZXRjX2hvc3RzOiB0cnVlCgp1c2VyczoKICAtIG5hbWU6IHVidW50dQogICAgc3NoLWF1dGhvcml6ZWQta2V5czoKICAgICAgLSBzc2gtcnNhIEFBQUFCM056YUMxeWMyRUFBQUFEQVFBQkFBQUJBUUNVQ25XNjJPUmlMNWN4VFJsNVN1VDdGMXNjZzgwZnJnTlA3bEFUbTJqOU80WFhFMFV0dGlkd3hIaGNhbVlWL0R0WDU3dHB5S2V3dVpOaXZ4UmZDNVJzQ3dObnZ6UTFZM01xTk9QckV3eXo5cjYyZDZrRzFid3RBQlAzMDJzNzBuTVZ5eTNtOXVHdEJDbDhHSkhPSWc3blNFcnpBeFlBb2k5dmNYeHFaNk1aSmUrc1hOc2U4QnhsbmhLUzQwUElseEtGck9XQTRyc0REYnFna1RWTWMzTDk5Vk4wRTkzbjZzYUMydFZGbWEvRGlRK2F6dk1VUk9OL0ZGMm0vNTJ3aFlyM2xrbDJWY2taVUNLaE9SclArdjVVRDB4YldMSkZCWEMxWVNqUUhlejZaa04xWFFGNEgrTUJiK0M2eUNLUzhMSXRZbkpnempIQ3FwMFhEN1BtdlpsagogICAgc3VkbzogWyJBTEw9KEFMTCkgTk9QQVNTV0Q6QUxMIl0KICAgIHNoZWxsOiAvYmluL2Jhc2gKCmNocGFzc3dkOgogIGxpc3Q6IHwKICAgIHVidW50dTprZWxvbXBvazE5YWRtaW4KICBleHBpcmU6IGZhbHNlCgpzc2hfcHdhdXRoOiB0cnVlCgpydW5jbWQ6CiAgLSBlY2hvICJuYW1lc2VydmVyIDguOC44LjgiID4gL2V0Yy9yZXNvbHYuY29uZgo=
```
- And you're done. The content of the **cloud-init.b64** will be used as the "userdata" when you're making a new instance via the CloudMonkey CLI.
## XII. Make a New Instance
### With Shared Network
- Enter the Cloudmonkey CLI:
```bash!
cloudmonkey
```
- Create a new network:
```bash!
## Retrieve your Zone ID
list zones
list physicalnetworks zoneid=[YOUR-ZONE-ID]
## Example: list physicalnetworks zoneid=02a8b1b0-9c1e-480c-9d13-9ae780d51905
list networkofferings
## Pick the one with the name "DefaultSharedNetworkOffering"
create network name=SharedNetwork01 displaytext=SharedNetwork01 networkofferingid=e4731a8e-31b5-482f-a0e1-3d5746edc81b zoneid=02a8b1b0-9c1e-480c-9d13-9ae780d51905 gateway=192.168.103.1 netmask=255.255.255.0 startip=192.168.103.230 endip=192.168.103.240 vlan=untagged physicalnetworkid=6ce7b56a-a7b9-495f-be94-ed9e8c5ad1b2
```
- Create a new instance. For the template ID, we are using the ID of the Ubuntu Cloud Image that we registered as a template in the "Images>Templates" menu on the CloudStack GUI directly:
```bash!
deploy virtualmachine name=Ubuntu-22-01 templateid=abbfef47-476e-4518-9e5f-a1a901c45819 serviceofferingid=eb6c8ea9-2eb6-4c35-89bf-e3d5f70df23c zoneid=02a8b1b0-9c1e-480c-9d13-9ae780d51905 networkids=8593971a-0cf7-4778-84e2-52067eadf540 keypair=myrsa userdata=I2Nsb3VkLWNvbmZpZwpob3N0bmFtZToga2Vsb21wb2sxOS12bQptYW5hZ2VfZXRjX2hvc3RzOiB0cnVlCgp1c2VyczoKICAtIG5hbWU6IHVidW50dQogICAgc3NoLWF1dGhvcml6ZWQta2V5czoKICAgICAgLSBzc2gtcnNhIEFBQUFCM056YUMxeWMyRUFBQUFEQVFBQkFBQUJBUUNVQ25XNjJPUmlMNWN4VFJsNVN1VDdGMXNjZzgwZnJnTlA3bEFUbTJqOU80WFhFMFV0dGlkd3hIaGNhbVlWL0R0WDU3dHB5S2V3dVpOaXZ4UmZDNVJzQ3dObnZ6UTFZM01xTk9QckV3eXo5cjYyZDZrRzFid3RBQlAzMDJzNzBuTVZ5eTNtOXVHdEJDbDhHSkhPSWc3blNFcnpBeFlBb2k5dmNYeHFaNk1aSmUrc1hOc2U4QnhsbmhLUzQwUElseEtGck9XQTRyc0REYnFna1RWTWMzTDk5Vk4wRTkzbjZzYUMydFZGbWEvRGlRK2F6dk1VUk9OL0ZGMm0vNTJ3aFlyM2xrbDJWY2taVUNLaE9SclArdjVVRDB4YldMSkZCWEMxWVNqUUhlejZaa04xWFFGNEgrTUJiK0M2eUNLUzhMSXRZbkpnempIQ3FwMFhEN1BtdlpsagogICAgc3VkbzogWyJBTEw9KEFMTCkgTk9QQVNTV0Q6QUxMIl0KICAgIHNoZWxsOiAvYmluL2Jhc2gKCmNocGFzc3dkOgogIGxpc3Q6IHwKICAgIHVidW50dTprZWxvbXBvazE5YWRtaW4KICBleHBpcmU6IGZhbHNlCgpzc2hfcHdhdXRoOiB0cnVlCgpydW5jbWQ6CiAgLSBlY2hvICJuYW1lc2VydmVyIDguOC44LjgiID4gL2V0Yy9yZXNvbHYuY29uZgo=
```

### XIII. Resetting CloudStack (Optional)
> If you made a mistake and want to wipe and reinstall CloudStack cleanly:
```
systemctl stop cloudstack-management cloudstack-agent
mysql -u root -p -e "DROP DATABASE cloud;"
rm -rf /var/lib/cloudstack /etc/cloudstack /var/log/cloudstack
rm -rf /export/primary/* /export/secondary/*
```
