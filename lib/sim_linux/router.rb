#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require 'json'
require_relative 'nis'
require_relative 'algo'
require_relative 'log'

# name of this router
name = ARGV[0]

# exit gracefully if no directory
if( !File.exist?(name + '/config.json') )
   exit(0)
end

# wait until there is a 'run' file
if( !File.exist?('run') )
   puts( "waiting until run file exists" )
   while( !File.exist?('run') )
      sleep(1)
   end
end

puts("starting")

# get the config
cfg_json = File.read(name + '/config.json')
cfg = JSON.parse(cfg_json)

# setup the Info service to handle IPv4 customer addresses
TEZC::Info::Customer.handle(:ipv4, TEZC::Info::CustomerIPv4)

# create the Algo
algo = TEZC::SimLinux::Algo.new(name, 3)

# create the log
log = TEZC::SimLinux::Log.new(name)

# create the NIS
nis = TEZC::SimLinux::NIS.new(name, 3, cfg["ports"].size, algo, log)

# do the common initialization
nis.common_init()

# configure the ports
cfg['ports'].each do |pd|
   if( pd[1] == 'core' )
      nis.core_add(pd[0], pd[2], pd[3])

   elsif( pd[1] == 'customer' )
      cust = {
         type: :ipv4,
         addr: pd[2]
      }
      nis.client_add(pd[0], cust, pd[3])
   else
      raise "invalid port type"
   end
end

# apply the specified demands
cfg["demands"].each_index do |ix|
   dm = cfg["demands"][ix]
   num = 1000 + ix
   port = dm[0]
   cust = {
      type: :ipv4,
      addr: dm[1]
   }
   prio = dm[2]
   speed = dm[3]
   nis.demand_set(num, cust, port, prio, speed)
end

puts("setup done!")

nis.run()

puts("exiting")