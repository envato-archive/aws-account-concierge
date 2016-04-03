#!/usr/bin/env ruby
require 'yaml'
require 'pp'
require './lib/concierge/utils'

# Config items to consider unless overriden on command line
DEFAULT_CONFIG_ITEMS = %w(roles groups s3 cloudtrail alarms account sns)

# Load everything in the handlers directory
project_root = File.dirname(File.absolute_path(__FILE__))
Dir.glob(project_root + '/lib/concierge/handlers/*') { |file| require file }

config_filename = ARGV.shift
begin
  config = YAML.load_file(config_filename)
  puts "Loaded config from #{config_filename}"
rescue
  puts "Please supply path to valid config file as first argument, unable to load '#{config_filename}'"
  exit
end

if ARGV.empty?
  config_items_to_do = DEFAULT_CONFIG_ITEMS
else
  config_items_to_do = ARGV
end
puts "Will act only on #{config_items_to_do.join(' ')} sections"

config_items_to_do.each do |item|
  next unless config.key?(item)
  puts "Working on #{item} section"
  handler = Concierge::Handlers.const_get(item.capitalize)
  printf Concierge::Utils.cleanup_output(handler.sync(config[item]))
  puts 'Done'
end
