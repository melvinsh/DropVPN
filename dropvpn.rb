require 'pry'
require 'sshkey'
require 'droplet_kit'

token = ENV['DO_TOKEN']
client = DropletKit::Client.new(access_token: token)

key = SSHKey.generate(type: 'RSA', bits: 2048)
ssh_key = DropletKit::SSHKey.new(public_key: key.ssh_public_key, name: 'DropVPN')

created_key = client.ssh_keys.create(ssh_key)

droplet = DropletKit::Droplet.new(
  name: 'DropVPN-Netherlands',
  image: 'ubuntu-16-04-x64',
  size: '512mb',
  region: 'ams3',
  ssh_keys: [created_key.id]
)

created = client.droplets.create(droplet)
