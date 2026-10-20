#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require 'json'
require_relative '../algo/avoid_cong'
require_relative '../info/records'
require_relative '../algo/demand'

module TEZC
module SimLinux
  
##########################################################################
# Routing Algorithm
class Algo

#################################################
# new algorithm
# 
# @param name [String] the name of the mininet instance
# @param max_level [Integer] max hierarchical levels
# 
def initialize(name, max_level)

   # save the name
   @name = name
   @max_level = max_level

   # pids of the routing process
   @pid = Array.new(max_level)
   @file_keep = Array.new(max_level)
   @start = Array.new(max_level)

   # the sequence number
   @seq = 0

   # clean up old routing files
   Dir.open(name) do |dir|
      dir.each_child do |fn|
         if( fn.start_with?( 'route' ) )
            File.delete(File.join(name, fn))
         end
      end
   end
  
end # def initialize()


#################################################
# start the routing algorithm
# 
# @param data [Object] the data we need to route
# 
def route(data)

   level = data[:level]
   @seq = @seq + 1

   # check if already running
   if( @pid[level-1] )
      raise "Already routing level %d" % level
   end

   # generate the hash
   he_d = {}
   data[:fills].each_pair do |num, rd|
      he_d[num] = rd.encode
   end
   he_p = {}
   data[:paths].each_pair do |num, rp|
      he_p[num] = rp.encode
   end
   he_w = {
      level: data[:level],
      links: data[:links].map{|ld| ld.encode },
      demands: data[:demands].map{|td| td.encode },
      fills: he_d,
      paths: he_p
   }

   # generate JSON
   json_w = JSON.pretty_generate(he_w)

   # open the files
   fn_in = File.join(@name, 'route-%d-%d-input.json' % [level, @seq])
   fn_out = File.join(@name, 'route-%d-%d-output.json' % [level, @seq])
   file_in = File.open( fn_in, 'w+b' )
   file_out = File.open( fn_out, 'w+b' )

   # write JSON to the file
   file_in.write(json_w)
   file_in.flush
  
   # fork
   pid = Kernel.fork()
   if( pid )
      @pid[level-1] = pid
      @start[level-1] = Time.now
      @file_keep[level-1] = file_out

      file_in.close
      return pid
   end

   ###########################
   # Running in a new process
   
   # read JSON from the file
   file_in.rewind
   json_r = file_in.read
   he_r = JSON.parse(json_r)
   file_in.close

   # generate the data
   cdem = {}
   he_r["fills"].each_pair do |num, re|
      cdem[num] = TEZC::Info::Records::Fill.decode(re)
   end
   cpth = {}
   he_r["paths"].each_pair do |num, re|
      cpth[num] = TEZC::Info::Records::Path.decode(re)
   end
   data_r = {
      level: he_r["level"],
      links: he_r["links"].map{|re|
            TEZC::Info::Records::Link.decode(re) },
      demands: he_r["demands"].map{|re|
            TEZC::Algorithm::Demand.decode(re) },
      fills: cdem,
      paths: cpth
   }

   # route it
   fn_route = File.join(@name, 'route-%d-%d.tsv' % [level, @seq])
   file = File.open(fn_route, 'w')
   algo = TEZC::Algorithm::AvoidCong.new(file)
   results = algo.route(data_r)
   file.close

   # generate the hash
   demands_hash = {}
   results[:fills].each_pair do |num, rd|
      demands_hash[num] = rd.encode
   end
   paths_hash = {}
   results[:paths].each_pair do |num, rp|
      paths_hash[num] = rp.encode
   end
   rh = {
      "level" => results[:level],
      "fills" => demands_hash,
      "paths" => paths_hash,
   }

   # write JSON to the file
   json_o = JSON.pretty_generate(rh)
   file_out.write(json_o)
   file_out.flush
   file_out.close

   exit(0)
   
end # def route()


#################################################
# check for routing results
def check()

   # no route running
   return nil if( !@pid.any? )

   # check if there is a finished child process
   # exits by exception if none
   pid = Process.wait(-1, Process::WNOHANG)
   return nil if( !pid )

   # find the finished child
   ix = @pid.find_index(pid)
   if( !ix )
      raise 'Unknown child exited %d' % pid
   end

   # record that running is done
   @pid[ix] = nil

   # read JSON from the file
   @file_keep[ix].rewind
   json = @file_keep[ix].read
   @file_keep[ix].close
   @file_keep[ix] = nil
   he = JSON.parse(json)

   # generate the results
   demands = {}
   he["fills"].each_pair do |num, he|
      demands[num.to_i] = Info::Records::Fill.decode(he)
   end
   paths = {}
   he["paths"].each_pair do |num, he|
      paths[num.to_i] = Info::Records::Path.decode(he)
   end
   results = {
      level: he["level"],
      fills: demands,
      paths: paths,
      start: @start[ix],
      finish: Time.now
   }

   return results
  
rescue Errno::ECHILD
   return nil
end # def check()
  
end # class TEZC::SimLinux::Algo
   
end # module TEZC::SimLinux
end # module TEZC