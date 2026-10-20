#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require 'digest'

module TEZC
module Info

##########################################################################
# Records
#
# Information that is replicated across an area
#
module Records

#################################################
# Generate ID for a routers
# 
# @param rand [String] random seed
# 
def self.id_router(rand)
   return Digest::SHA256.hexdigest(
      'router %s' % [rand])[0,32].freeze
end # def self.id_router()


#################################################
# Generate ID for an node
# 
# @param leader [String] the leader ID
# @param level [Integer] the level
# @param partition [Integer] the partition number
# 
def self.id_node(leader, level, partition)
   return Digest::SHA256.hexdigest(
      'area %s %d %d' % [leader, level, partition])[0,32].freeze
end # def self.id_node()


#################################################
# Generate ID for a link description
# 
# @param router [String] the router ID
# @param port [Integer] the port
# 
def self.id_link(router, port)
   return Digest::SHA256.hexdigest(
         'link %s %d' % [router, port])[0,32].freeze
end # def self.id_link()


#################################################
# Generate ID for an address assignment
# 
# @param leader [String] the leader ID
# @param level [Integer] the level
# @param addr [Integer] the address being assigned
# 
def self.id_addr(leader, level, addr)
   return Digest::SHA256.hexdigest(
      'address %s %d %d' % [leader, level, addr])[0,32].freeze
end # def self.id_addr()


#################################################
# Generate ID for an routed demand
#
# @param leader [String] the leader ID
# @param level [Integer] the level
# @param fnum [Integer] the fill number
# 
def self.id_fill(leader, level, fnum)
   return Digest::SHA256.hexdigest(
      'fill %s %d %d' % [leader, level, fnum])[0,32].freeze
end # def self.id_fill()


#################################################
# Generate ID for an routed path
#
# @param leader [String] the leader ID
# @param level [Integer] the level
# @param pnum [Integer] the path number
# 
def self.id_path(leader, level, pnum)
   return Digest::SHA256.hexdigest(
      'path %s %d %d' % [leader, level, pnum])[0,32].freeze
end # def self.id_path()


#################################################
# Generate ID for egress info
#
# @param router [String] the router ID
# 
def self.id_egress(router)
   return Digest::SHA256.hexdigest(
      'egress %s' % [router])[0,32].freeze
end # def self.id_egress()


#################################################
# Generate ID for traffic demand
#
# @param router [String] the router ID
# @param dnum [Integer] the demand number
# 
def self.id_demand(router, dnum)
   return Digest::SHA256.hexdigest(
      'demand %s %d' % [router, dnum])[0,32].freeze
end # def self.id_demand()


#################################################
# Label for a node address
#
# @param lev (see #label_path)
# @param pri [Integer] the priority
# @param node [Integer] the node number 
# @return (see #label_path)
def self.label_node(lev, pri, node)
   return (lev << 17) + 0x1f800 + (pri << 8) + node 
end # def label_node()


#################################################
# Label for a path label
#
# @param lev [Integer] the level
# @param path [Intger] the path label
# @return [Integer] the label
#
def self.label_path(lev, path)
   return (lev << 17) + path
end # def label_path()


#################################################
# Label for an end of path
# @return [Integer]
LABEL_EOP = 0x200


##########################################################################
# Parent class for a record
class Base

#################################################
# @return [String] the item ID
attr_accessor :id

#################################################
# the hierarchical level
# @return [Integer]
attr_accessor :level

#################################################
# @return [Symbol] the item type
attr_reader :type

#################################################
# @return [Integer] the item serial
attr_accessor :serial


end # class TEZC::Info::Records::Base
##########################################################################


##########################################################################
# Link Descriptor
class Link < Base

#################################################
# New link descriptor
def initialize()
   @type = :link
end # def initialize()

#################################################
# @return [Integer] speed
attr_accessor :speed

#################################################
# @return [String] router ID
attr_accessor :routerA, :routerB

#################################################
# @return [Integer] the port number
attr_accessor :portA, :portB

#################################################
# @return [String] the node ID
attr_accessor :nodeA, :nodeB

#################################################
# @return [Array] the address
attr_accessor :addrA, :addrB

#################################################
# encode as Hash
def encode
   return {
      "id" => @id,
      "type" => @type,
      "level" => @level,
      "serial" => @serial,
      "speed" => @speed,
      "routerA" => @routerA,
      "routerB" => @routerB,
      "portA" => @portA,
      "portB" => @portB,
      "nodeA" => @nodeA,
      "nodeB" => @nodeB,
      "addrA" => @addrA.dup,
      "addrB" => @addrB.dup,
   }
end # def encode()

#################################################
# decode from Hash
def self.decode(he)
   ld = self.new()
   ld.id = he["id"]
   ld.level = he["level"]
   ld.serial = he["serial"]
   ld.speed = he["speed"]
   ld.routerA = he["routerA"]
   ld.routerB = he["routerB"]
   ld.portA = he["portA"]
   ld.portB = he["portB"]
   ld.nodeA = he["nodeA"]
   ld.nodeB = he["nodeB"]
   ld.addrA = he["addrA"]
   ld.addrB = he["addrB"]

   return ld
end # def self.decode()

end # class TEZC::Info::Records::Link
##########################################################################


##########################################################################
# Address Assignment
class Addr < Base

#################################################
# New address assignment
def initialize()
   @type = :addr
end # def initialize()

#################################################
# @return [String] area ID
attr_accessor :area

#################################################
# @return [Integer] the assigned address
attr_accessor :addr

#################################################
# @return [String] node ID
attr_accessor :node

end # class TEZC::Info::Records::Addr
##########################################################################


##########################################################################
# Egress Information
class Egress < Base

#################################################
# New egress info
def initialize()
   @type = :egress
end # def initialize()

#################################################
# The sending router
# @return [String]
attr_accessor :router

#################################################
# The sending router address
# @return [Array(Integer)]
attr_accessor :address

#################################################
# the list of customer network prefixes
# @return [Array]
attr_accessor :customer

end # class TECZ::Info::Records::Egress
##########################################################################


##########################################################################
# A traffic demand
# 
class Demand < Base
   
#################################################
# New traffic demand
def initialize()
   @type = :demand
end # def initialize()

#################################################
# The sending router
# @return [String]
attr_accessor :router

#################################################
# The priority level
# 
# Lower numbers are higher priority.
# Level 0 is reserved for demands generated by
# higher level routing results.
# 
# @return [Integer]
attr_accessor :priority

#################################################
# The source address
# @return [Array(Integer)]]
attr_accessor :source

#################################################
# The destination address
# @return [Array(Integer)]
attr_accessor :destination

#################################################
# the requested speed
# @return [Integer]
attr_accessor :speed

end # class TECZ::Info::Records::Demand
##########################################################################


##########################################################################
# A filled demand
class Fill < Base

#################################################
# New route demand
def initialize()
   @type = :fill
end # def initialize()

#################################################
# the area ID
# 
# @return [String]
attr_accessor :area

#################################################
# the demand number
# @return [Integer]
attr_accessor :demand

#################################################
# source address
# @return [Array(Integer)]
attr_accessor :source

#################################################
# destination address
# @return [Integer]
attr_accessor :destination

#################################################
# priority
# @return [Integer]
attr_accessor :priority

#################################################
# path
# @return [Integer]
attr_accessor :path

#################################################
# the placed speed
# @return [Integer]
attr_accessor :speed

#################################################
# the total requested speed
# @return [Integer]
attr_accessor :speed_request

#################################################
# encode as Hash
def encode()
   return {
      "id" => @id,
      "type" => @type,
      "level" => @level,
      "serial" => @serial,
      "area" => @area,
      "demand" => @demand,
      "destination" => @destination,
      "priority" => @priority,
      "path" => @path,
      "source" => @source.dup,
      "speed" => @speed,
      "speed_request" => @speed_request
   }
end # def encode()


#################################################
# decode from Hash
def self.decode(he)
   rd = self.new

   rd.id = he["id"]
   rd.level = he["level"]
   rd.serial = he["serial"]
   rd.area = he["area"]
   rd.demand = he["demand"]
   rd.destination = he["destination"]
   rd.priority = he["priority"]
   rd.path = he["path"]
   rd.source = he["source"]
   rd.speed = he["speed"]
   rd.speed_request = he["speed_request"]

   return rd
end # def self.decode()

end # class TEZC::Info::Records::Fill
##########################################################################


##########################################################################
# A filled path
class Path < Base

#################################################
# New route demand
def initialize()
   @type = :path
end # def initialize()


#################################################
# the area ID
# @return [String]
attr_accessor :area

#################################################
# path number
# @return [Integer]
attr_accessor :path

#################################################
# links to follow
# @return [Array(RouteLink)]
attr_accessor :link

##########################################################################
# A link that forms part of the routed path
class PathLink

#################################################
# the origin address
# @return [Array(Integer)]
attr_accessor :addr_orig

#################################################
# the termination address
# @return [Array(Integer)]
attr_accessor :addr_term

#################################################
# the origin label
# @return [Integer]
attr_accessor :label

#################################################
# The origin router
attr_accessor :router

#################################################
# The origin port
attr_accessor :port

#################################################
# encode to Hash
def encode()
   return {
      "addr_orig" => @addr_orig.dup,
      "addr_term" => @addr_term.dup,
      "label" => @label,
      "router" => @router,
      "port" => @port,
   }
end # def encode()


#################################################
# decode from Hash
def self.decode(he)
   rl = self.new()

   rl.addr_orig = he["addr_orig"]
   rl.addr_term = he["addr_term"]
   rl.label = he["label"]
   rl.router = he["router"]
   rl.port = he["port"]

   return rl  
end # def self.decode()

end # class TEZC::Info::Records::Path::PathLink
##########################################################################

#################################################
# encode to Hash
def encode()
   return {
      "id" => @id,
      "type" => @type,
      "level" => @level,
      "serial" => @serial,
      "area" => @area,
      "path" => @path,
      "link" => @link.map{|rl| rl.encode}
   }
end # def encode()


#################################################
# decode from Hash
def self.decode(he)
   rp = self.new()

   rp.id = he["id"]
   rp.level = he["level"]
   rp.serial = he["serial"]
   rp.area = he["area"]
   rp.path = he["path"]
   rp.link = he["link"].map{|re| PathLink.decode(re)}

   return rp
end # def self.decode()  

end # class TEZC::Info::Records::Path
##########################################################################

end # module TEZC::Info::Records

end # module TEZC::Info
end # module TEZC