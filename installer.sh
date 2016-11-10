#!/bin/bash

newclient () {
  # Generates the custom client.ovpn
  cp /etc/openvpn/client-common.txt ~/$1.ovpn
  echo "<ca>" >> ~/$1.ovpn
  cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
  echo "</ca>" >> ~/$1.ovpn
  echo "<cert>" >> ~/$1.ovpn
  cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
  echo "</cert>" >> ~/$1.ovpn
  echo "<key>" >> ~/$1.ovpn
  cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
  echo "</key>" >> ~/$1.ovpn
  echo "<tls-auth>" >> ~/$1.ovpn
  cat /etc/openvpn/ta.key >> ~/$1.ovpn
  echo "</tls-auth>" >> ~/$1.ovpn
}

# Try to get our IP from the system and fallback to the Internet.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
    IP=$(wget -qO- ipv4.icanhazip.com)
fi

PORT=1194
CLIENT=dropvpn

apt-get update
apt-get install openvpn iptables openssl ca-certificates -y
# An old version of easy-rsa was available by default in some openvpn packages
if [[ -d /etc/openvpn/easy-rsa/ ]]; then
  rm -rf /etc/openvpn/easy-rsa/
fi

# Get easy-rsa
cd /tmp
wget https://github.com/OpenVPN/easy-rsa/releases/download/3.0.1/EasyRSA-3.0.1.tgz
tar -xzf /tmp/EasyRSA-3.0.1.tgz
mv /tmp/EasyRSA-3.0.1/ /etc/openvpn/easy-rsa/
chown -R root:root /etc/openvpn/easy-rsa/
cd /etc/openvpn/easy-rsa/

# Create the PKI, set up the CA, the DH params and the server + client certificates
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa gen-dh
./easyrsa build-server-full server nopass
./easyrsa build-client-full $CLIENT nopass
./easyrsa gen-crl

# Move the stuff we need
cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn
  
# CRL is read with each client connection, when OpenVPN is dropped to nobody
chown nobody:nogroup /etc/openvpn/crl.pem
  
# Generate key for tls-auth
openvpn --genkey --secret /etc/openvpn/ta.key
  
# Generate server.conf
echo "port $PORT
proto udp
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt" > /etc/openvpn/server.conf
  
echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf
  
grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
  echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf;
done

echo "keepalive 10 120
cipher AES-256-CBC
comp-lzo
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem" >> /etc/openvpn/server.conf

# Enable net.ipv4.ip_forward for the system
sed -i '/\<net.ipv4.ip_forward\>/c\net.ipv4.ip_forward=1' /etc/sysctl.conf
if ! grep -q "\<net.ipv4.ip_forward\>" /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi

# Avoid an unneeded reboot
echo 1 > /proc/sys/net/ipv4/ip_forward

# Set NAT for the VPN subnet
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" /etc/rc.local

if iptables -L -n | grep -qE 'REJECT|DROP'; then
  iptables -I INPUT -p udp --dport $PORT -j ACCEPT
  iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
  iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
  sed -i "1 a\iptables -I INPUT -p udp --dport $PORT -j ACCEPT" /etc/rc.local
  sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" /etc/rc.local
  sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" /etc/rc.local
fi

# And finally, restart OpenVPN
systemctl restart openvpn@server

# client-common.txt is created so we have a template to add further users later
echo "client
dev tun
proto udp
sndbuf 0
rcvbuf 0
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
comp-lzo
setenv opt block-outside-dns
key-direction 1
verb 3" > /etc/openvpn/client-common.txt

# Generates the custom client.ovpn
newclient "$CLIENT"
echo ""
echo "Finished!"
echo ""
echo "Your client config is available at ~/$CLIENT.ovpn"

