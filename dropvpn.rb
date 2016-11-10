require 'pry'
require 'sshkey'
require 'net/ssh'
require 'net/scp'
require 'droplet_kit'

puts '[Info] Connecting to client...'
token = ENV['DO_TOKEN']
client = DropletKit::Client.new(access_token: token)

puts '[Info] Generating SSH keys...'
key = SSHKey.generate(type: 'RSA', bits: 2048)
ssh_key = DropletKit::SSHKey.new(public_key: key.ssh_public_key, name: 'DropVPN')

created_key = client.ssh_keys.create(ssh_key)

puts '[Info] Creating droplet...'
droplet = DropletKit::Droplet.new(
  name: 'DropVPN-Netherlands',
  image: 'ubuntu-16-04-x64',
  size: '512mb',
  region: 'ams3',
  ssh_keys: [created_key.id]
)

created = client.droplets.create(droplet)

puts '[Info] Waiting for droplet to start...'
sleep 40

puts '[Info] Attempting to get external IP...'
ip = client.droplets.find(id: created.id).networks.v4.first.ip_address

puts ip

puts '[Info] Connecting to server and installing OpenVPN...'
Net::SSH.start(ip, 'root', key_data: key.private_key) do |ssh|
  ssh.scp.upload! 'installer.sh', '/root/installer.sh'
  ssh.exec!('chmod +x installer.sh')
  ssh.exec!('./installer.sh')
  ssh.scp.download! '/root/dropvpn.ovpn', 'dropvpn.ovpn'
  break
end

puts '[Info] Done! Configuration file saved to dropvpn.ovpn.'

# client.droplets.delete(id: created.id)
