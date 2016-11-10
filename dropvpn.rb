require 'pry'
require 'droplet_kit'

token = ENV['DO_TOKEN']
client = DropletKit::Client.new(access_token: token)

binding.pry

droplet = DropletKit::Droplet.new(name: 'DropVPN-Netherlands', image: 'ubuntu-16-04-x64', size: '512mb', region: 'ams3')
client.droplets.create(droplet)
