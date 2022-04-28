#!/bin/bash
# You will used three files at the same time: lxd.config,cert.crt,init.sh; 
# Info：
    # Maintance: ; 
    # Mail:"zhaochunjiang1@huawei.com"; 
    # Created by 2022-02-15;
# Only use for Baremetal-server-node: 
    # OS Version: eulerOS:2.3;

## Configure basic configuration in node for all envrionment 
echo "#############################################################################################"
# add yum registry
rm -f /etc/yum.repos.d/*
cat > /etc/yum.repos.d/EulerOS-base.repo <<-EOF
[EulerOS-base]
name=EulerOS-base
baseurl=http://repo.huaweicloud.com/euler/2.3/os/x86_64/
enabled=1
gpgcheck=1
gpgkey=http://repo.huaweicloud.com/euler/2.3/os/RPM-GPG-KEY-EulerOS
EOF

cat > /etc/yum.repos.d/EulerOS-2.0SP3-Base.repo <<-EOF
[EulerOS-2.0SP3-base]
name=eulerOS-2.0SP3-Base-repo.huaweicloud.com
baseurl=https://repo.huaweicloud.com/centos/7/os/$basearch/
gpgcheck=0
gpgkey=https://repo.huaweicloud.com/centos/RPM-GPG-KEY-CentOS-7

[EulerOS-2.0SP3-updates]
name=eulerOS-2.0SP3-Updates-repo.huaweicloud.com
baseurl=https://repo.huaweicloud.com/centos/7/updates/$basearch/
gpgcheck=0
gpgkey=https://repo.huaweicloud.com/centos/RPM-GPG-KEY-CentOS-7

[EulerOS-2.0SP3-extras]
name=eulerOS-2.0SP3-Extras-repo.huaweicloud.com
baseurl=https://repo.huaweicloud.com/centos/7/extras/$basearch/
gpgcheck=0
gpgkey=https://repo.huaweicloud.com/centos/RPM-GPG-KEY-CentOS-7

[EulerOS-2.0SP3-plus]
name=eulerOS-2.0SP3-Plus-repo.huaweicloud.com
baseurl=https://repo.huaweicloud.com/centos/7/centosplus/$basearch/
gpgcheck=0
enabled=0
gpgkey=https://repo.huaweicloud.com/centos/RPM-GPG-KEY-CentOS-7
EOF

cat > /etc/yum.repos.d/epel.repo <<-EOF
[EulerOS-epel]
name=Extra Packages for EulerOS - $basearch
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-7&arch=$basearch&infra=$infra&content=$contentdir
failovermethod=priority
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

[EulerOS-epel-debuginfo]
name=Extra Packages for EulerOS - $basearch - Debug
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-debug-7&arch=$basearch&infra=$infra&content=$contentdir
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=1

[EulerOS-epel-source]
name=Extra Packages for EulerOS - $basearch - Source
metalink=https://mirrors.fedoraproject.org/metalink?repo=epel-source-7&arch=$basearch&infra=$infra&content=$contentdir
failovermethod=priority
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
gpgcheck=1
EOF
yum repolist && yum clean all && yum update && yum makecache fast && yum install selinux-policy-targeted -y

## install lxc  
echo "#############################################################################################"
# check files
if [ ! -e ./cert.crt ] || [ ! -e ./lxd.config ];then
        echo "miss init files"
        exit
fi

# yum install snapd
yum install snapd -y
if [[ -z `rpm -qa | grep "snapd"` ]];then
        echo "install snapd faild"
        exit
fi
systemctl enable --now snapd.socket
ln -s /var/lib/snapd/snap /snap

# lxd install
while :
do
        echo "installing lxd......"
        sleep 10
        snap install lxd --channel=4.20/stable
        if [ $? -eq 0 ];then
                echo "snap install succeeded"
                break
        else
            echo "install faild this time,try again.please wait......"
        fi
done
export PATH="$PATH:/snap/bin"
/usr/bin/env | grep -w '/snap/bin'
if [ $? -ne 0 ];then
        echo "snap envrionment path not exist"
        exit
fi

# lxd config
str=`ip add | grep "bond0" | tail -1 | awk '{print $2}'`
sed -i "s/ip_add/${str%/*}/g" ./lxd.config
sed -i "s/eth0/bond0/g" ./lxd.config
sed -i "s/vdc/sdc/g" ./lxd.config
if [ ! -e /dev/sdc ];then
        echo "miss data disk"
        exit
fi
lxd init --preseed < ./lxd.config
if [ $? -ne 0 ];then
        echo "lxd init faild"
        exit
else
        echo "lxd init succeeded"
fi
lxc config trust add internal ./cert.crt
if [ $? -ne 0 ];then
        echo "lxc cert import faild"
        exit
else
        echo "lxc cert import succeeded"
fi

# iptables rules
ebtables -N ip_isolate
ebtables -P ip_isolate DROP
ebtables -A FORWARD -p ip -i veth+ -j ip_isolate
ebtables -A ip_isolate -p ip -i veth+ --ip-src 10.205.172.1/24 --ip-dst 10.205.172.1 -j ACCEPT
ebtables -A ip_isolate -p ip -i veth+ --ip-src 10.205.172.1 --ip-dst 10.205.172.1/24 -j ACCEPT
ebtables -A ip_isolate -p ip -i veth+ --ip-src 10.205.172.1/24 --ip-dst 10.205.172.1/24 -j DROP
# arp rules
ebtables -N flood_secure
ebtables -P flood_secure DROP
ebtables -I FORWARD 1 -d ff:ff:ff:ff:ff:ff -j flood_secure
ebtables -A flood_secure -s 00:16:3e:a1:a2:a3 -i lxdbr0 -d ff:ff:ff:ff:ff:ff -j ACCEPT
ebtables -A flood_secure -p ARP -i lxdbr0 -j ACCEPT
ebtables -A flood_secure -p IPv4 -i ! lxdbr0 --ip-proto udp -j DROP
ebtables -A flood_secure -s 00:16:3e:00:00:00/00:16:3e:ff:ff:ff -i ! lxdbr0 -d ff:ff:ff:ff:ff:ff -j DROP
ebtables-save > /etc/sysconfig/ebtables
if [[ -z `grep -w "/usr/bin/cat" /etc/rc.d/rc.local` ]];then
        echo -e '/usr/bin/cat /etc/sysconfig/ebtables | ebtables-restore' >> /etc/rc.d/rc.local
        chmod +x /etc/rc.d/rc.local
fi

## check status
echo "#############################################################################################"
lxc info
systemctl stop sshd
systemctl disable sshd
rm -f ./cert.crt ./lxd.config ./init.sh
echo "init finish,system will be reboot..."
/usr/sbin/reboot
