#!/usr/bin/env ruby
require 'yaml'
require 'pp'
require './lib/concierge/utils'
require './lib/concierge/handlers/roles'
require './lib/concierge/handlers/policies'
require './lib/concierge/handlers/groups'
require './lib/concierge/handlers/s3'
require './lib/concierge/handlers/cloudtrail'
require './lib/concierge/handlers/alarms'
require './lib/concierge/handlers/account'
require './lib/concierge/handlers/sns'

begin
  config = YAML.load_file(ARGV[0].to_s)
rescue
  puts "Please supply path to valid config file as first and only argument Unable to load '#{ARGV[0].to_s}'"
  exit
end

# Which sections in the config to actually do
config_items_to_do = ['roles','groups','s3','cloudtrail','alarms', 'account', 'sns']

puts "Loaded config from #{ARGV[0].to_s}"
if ARGV.length > 1
  config_items_to_do = []
  ARGV[1,ARGV.length].each do |item|
    config_items_to_do.push(item)
  end
end
puts "Will act only on #{config_items_to_do.join(" ")} sections"

config_items_to_do.each do |item|
  next unless config.key?(item) 
  puts "Working on #{item} section"
  handler = Concierge::Handlers::const_get(item.capitalize)
  printf Concierge::Utils.cleanup_output(handler.sync(config[item]))
  puts 'Done'
end
