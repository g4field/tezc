#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative '../info/records'

module TEZC
module Algorithm

##########################################################################
# Base of the Routing Algorithms
class Base


   #################################################
# New routing algorithm
#
# @param file [File] the file to write to
#
def initialize(file)
   @file = file

   @link_class = Link
   @node_class = Node
end # def initialize()


###########################################################
###########################################################
# routing stuff

#################################################
# Route
#
# @param data [Hash] the input data
#
def route(data)

   # easy access variables
   lv_rt = data[:level]
   link_desc = data[:links]
   demand_algo = data[:demands]

   # write the input
   write_input(data)

   # build nodes & links model
   pre_model(link_desc)

   # sort demands by priority level
   pre_demands(demand_algo)

   # write the consolidated demands
   write_demands()

   # start numbering
   @num_demand = 1
   @num_path = 1
   @fills = {}
   @paths = {}
   @trail_start = {}
   @trail_end = {}
   
   # route by priority level
   lv_lst = @demands.keys.sort.reverse
   lv_lst.each do |lv|
     
      # route the level
      route_priority(lv)
     
      # build the fills
      post_fills(lv)

      # update the model
      post_model()

   end

   # create the routed paths
   post_paths()

   # return the results
   results = {
      level: lv_rt,
      fills: @fills,
      paths: @paths
   }
   write_results(results)
   return results

end # def route()


###########################################################
###########################################################
# pre-processing before routing 


#################################################
# Build the demand list
#
# Takes the raw input demands, consolidates those with the same
# destination node and source address, and sorts by priority.
# 
# @param demand_algo [Array(Algorithm::Demand)]
#   demands passed to the Algorithm
#   
def pre_demands(demand_algo)
   
   # consolidated demands
   demand_hash = {}

   # sorted by priority
   @demands = {}

   # go thru all inputs
   demand_algo.each_index do |ix|
      da = demand_algo[ix]

      # consolidate identical priority, dst node and src addr
      ary = [da.priority, da.destination.last] + da.source
      
      # existing demand, add requested speeds
      dm = demand_hash[ary]
      if( dm )
         dm.num.append(ix)
         dm.speed = dm.speed + da.speed

      # new demand
      else
         dm = Demand.new
         dm.num = [ ix ]
         dm.src = da.source.last
         dm.src_full = da.source.dup
         dm.dst = da.destination.last
         dm.speed = da.speed

         # list it on the priority sort
         ar = @demands[da.priority]
         if( !ar )
            ar = []
            @demands[da.priority] = ar
         end
         ar.append(dm)

         demand_hash[ary] = dm

         # sanity check
         if( !dm.src )
            raise "wtf"
         end
      end
      
   end

end # def pre_demands()


#################################################
# Build the node model
# 
# @param link_descs [Array(Info::Records::Link)] the links in the area
# @return [Hash(Node)] Nodes indexed by address of the node
# 
def pre_model(link_descs)

   @nodes = {}
   @links = []
   link_ix = 0

   # each link
   link_descs.each do |ld|

      # get/add nodes
      ndA = pre_node(ld.nodeA, ld.addrA.last)
      ndB = pre_node(ld.nodeB, ld.addrB.last)

      # link A
      lkA = @link_class.new()
      lkA.desc = ld
      lkA.desc_side = true
      lkA.speed_base = ld.speed
      lkA.speed_used = 0
      lkA.speed_avail = ld.speed
      lkA.node_ob = ndA
      lkA.ix_ob = ndA.link_ob.size
      lkA.node_ib = ndB
      lkA.ix_ib = ndB.link_ib.size
      @links.append(lkA)

      # link B
      lkB = @link_class.new()
      lkB.desc = ld
      lkB.desc_side = false
      lkB.speed_base = ld.speed
      lkB.speed_used = 0
      lkB.speed_avail = ld.speed
      lkB.node_ob = ndB
      lkB.ix_ob = ndB.link_ob.size
      lkB.node_ib = ndA
      lkB.ix_ib = ndA.link_ib.size
      @links.append(lkB)

      # pair them
      lkA.pair = lkB
      lkB.pair = lkA

      # add them to the nodes
      ndA.link_ob.append( lkA )
      ndB.link_ib.append( lkA )
      ndB.link_ob.append( lkB )
      ndA.link_ib.append( lkB )
     
   end

end # def pre_model()


#################################################
# Get or add a node to the model
#
# @param ni [String] the node ID
# @param ad [Integer] the node address
# 
def pre_node(ni, ad)
  
   # get the node
   nd = @nodes[ad]

   # add if needed
   if( !nd )
      nd = @node_class.new(ad)
      @nodes[ad] = nd
   end

   # set the id
   if( nd.id )
      if( nd.id != ni )
         raise "Node addresses are not consistent ad: %d nd %s ni %s" %
            [ad, nd.id, ni]
      end
   else
      nd.id = ni
   end

   return nd
end # def pre_node()


###########################################################
###########################################################
# post-processing after routing


#################################################
# Create Fills
# 
# Take the link list of a demand and construct the
# path and routed demand.
#
# trail_end is a Hash of dst addr to last Hop.
# trail_start is a Hash of path number to first Hop.
#
# @param priority [Integer] the priority
# 
def post_fills(priority)

   @demands[priority].each do |dm|

      # not placed
      next if( !dm.links )

      # start at the destination
      hop = @trail_end[dm.dst]
      if( !hop )
         hop = Hop.new
         hop.path = @num_path
         @num_path = @num_path + 1
         @trail_end[dm.dst] = hop
      end

      # walk the links back to the source building the trails
      dm.links.each do |lk|

         # existing trail
         if( hop.reverse && hop.reverse[lk.ix_ib] )
            prv_hop = hop.reverse[lk.ix_ib]

         # new hop
         else
            prv_hop = Hop.new
            prv_hop.node = lk.node_ob
            prv_hop.forward = hop
            prv_hop.link = lk.ix_ob

            # branch
            if( hop.reverse )
               prv_hop.path = @num_path
               @num_path = @num_path + 1

            # extend a trail
            else
               hop.reverse = {}
               prv_hop.path = hop.path
            end

            # point to us
            @trail_start[prv_hop.path] = prv_hop
            hop.reverse[lk.ix_ib] = prv_hop
         end

         # move to the previous hop
         hop = prv_hop
      end

      # create the routed demand
      rd = TEZC::Info::Records::Fill.new
      @fills[@num_demand] = rd
      rd.demand = @num_demand
      @num_demand = @num_demand + 1
      rd.source = dm.src_full.dup
      rd.destination = dm.dst
      rd.priority = priority
      rd.speed = dm.fill
      rd.speed_request = dm.speed
      rd.path = hop.path
   end

end # def post_fills()


#################################################
# Create paths from the hops entries
#
def post_paths()

   # create the routed paths
   @trail_start.each_pair do |num, src|

      # build the link list
      list = []
      hop = src
      while( hop.forward )
         # get the link
         lk = hop.node.link_ob[hop.link]
         ld = lk.desc

         # new link
         rl = TEZC::Info::Records::Path::PathLink.new
         if( lk.desc_side )
            rl.addr_orig = ld.addrA.dup
            rl.addr_term = ld.addrB.dup
            rl.router = ld.routerA
            rl.port = ld.portA
         else
            rl.addr_orig = ld.addrB.dup
            rl.addr_term = ld.addrA.dup
            rl.router = ld.routerB
            rl.port = ld.portB
         end
         rl.label = num # FIXME
         list.append( rl )

         hop = hop.forward
      end

      # make the path
      rp = TEZC::Info::Records::Path.new
      @paths[num] = rp
      rp.path = num
      rp.link = list
   end

end # def post_paths()


#################################################
# Commit the link usage
#
def post_model()
   @links.each{|lk| lk.speed_avail = lk.speed_base - lk.speed_used }
end # def post_model()


###########################################################
###########################################################
# write info


#################################################
# Write the input
def write_input(data)

   lv = data[:level]
   links = data[:links]
   demands = data[:demands]

   # write the inputs
   @file.write("\n\n#################################################\n")
   @file.write("Inputs\nlevel: %d\n" % lv)

   # links
   @file.write("\nlinks %d:\n" % links.size)
   @file.write("id\tspeed\tnodeA\trouterA\tportA\taddrA\tnodeB\trouterB\tportB\taddrB\n")
   links.each do |lnk|
      @file.write("%s\t%d\t%s\t%s\t%d\t%s\t%s\t%s\t%d\t%s\n" % [
         lnk.id, lnk.speed, 
         lnk.nodeA, lnk.routerA, lnk.portA, lnk.addrA.inspect,
         lnk.nodeB, lnk.routerB, lnk.portB, lnk.addrB.inspect,
      ])
   end

   # demands
   @file.write("\ndemands %d:\n" % demands.size)
   @file.write("id\torig\tpri\tsource\tdest\tspeed\n")
   demands.each do |dm|
      @file.write("%s\t%s\t%d\t%s\t%s\t%d\n" % [
         dm.id,
         (dm.original) ? 'Y' : 'N',
         dm.priority,
         dm.source.inspect, dm.destination.inspect,
         dm.speed
      ])
   end

   @file.flush

end # def write_input()


#################################################
# Write the consolidated demands
def write_demands()

   # header
   @file.write("\nconsolidated demands %d:\n" % @demands.values.flatten.size)
   @file.write("pri\tsrc\tdst\tspeed\tids\n")

   @demands.each_pair do |pri, ary|
      ary.each do |dm|
         @file.write("%d\t%d\t%d\t%d\t%s\n" % [
               pri,
               dm.src, dm.dst,
               dm.speed,
               dm.num.inspect
            ])
      end
   end

   @file.flush

end # def write_demands()


#################################################
# Write the results
def write_results(res)

   lv = res[:level]
   fills = res[:fills]
   paths = res[:paths]

   # write the results
   @file.write("\n\nResults\nlevel: %d\n" % lv)

   # fills
   @file.write("\nfills %d:\n" % fills.size)
   @file.write("num\tpri\tspeed\trequest\tsource\tdest\tpath\n")
   fills.each_value do |dm|
      @file.write("%d\t%d\t%d\t%d\t%s\t%d\t%d\n" % [
         dm.demand, dm.priority, dm.speed, dm.speed_request, 
         dm.source.inspect, dm.destination,
         dm.path,
      ])
   end

   # paths
   @file.write("\npaths %d:\n" % paths.size)
   @file.write("num\tlabel\taddr orig\taddr term\tlab term\trouter\tport\n")
   paths.each_value do |rp|
      rp.link.each do |rl|
         @file.write("%d\t%d\t%s\t%s\t%s\t%d\n" % [
            rp.path, rl.label,
            rl.addr_orig.inspect, 
            rl.addr_term.inspect,
            rl.router, rl.port
         ])
      end
   end

   @file.flush

end # def write_results()



##########################################################################
# A Demand used for a priority level route
class Demand

alias inspect to_s

#################################################
# The demand number
# @return [Array(Integer)]
attr_accessor :num

#################################################
# The source address
# @return [Integer]
attr_accessor :src

#################################################
# The complete source address
# @return [Array(Integer)]
attr_accessor :src_full

#################################################
# The destination address
# @return [Integer]
attr_accessor :dst

#################################################
# The requested speed
attr_accessor :speed

#################################################
# The links used to route between dst & src
# @return [Array(Link)]
attr_accessor :links

#################################################
# The filled speed
attr_accessor :fill

end # class TEZC::Algorithm::Base::Demand
##########################################################################


##########################################################################
# A node
class Node

alias inspect to_s

#################################################
# new node
def initialize(addr)
   @addr = addr
   @link_ib = []
   @link_ob = []
end # def initialize()

#################################################
# The node ID
# @return [String]
attr_accessor :id

#################################################
# Assigned address
# @return [Integer]
attr_reader :addr

#################################################
# Links going outbound
# @return [Array(Link)]
attr_accessor :link_ob

#################################################
# Links going inbound
# @return [Array(Link)]
attr_accessor :link_ib

end # class TEZC::Algorithm::Base::Node


##########################################################################
# A link
class Link

alias inspect to_s

#################################################
# The {Info::Records::Link}
# @return [Info::Records::Link]
attr_accessor :desc

#################################################
# A or B side of the underlying link
# @return [true,false] true for A, false for B
attr_accessor :desc_side

#################################################
# The other side of the link
# @return [Link]
attr_accessor :pair

#################################################
# Outbound node (from)
# @return [Node]
attr_accessor :node_ob

#################################################
# Index of the link in node_ob
# @return [Integer]
attr_accessor :ix_ob

#################################################
# Inbound node (to)
# @return [Node]
attr_accessor :node_ib

#################################################
# Index of the link in node_ib
# @return [Integer]
attr_accessor :ix_ib

#################################################
# The base speed
# @return [Integer]
attr_accessor :speed_base

#################################################
# The available speed, not already committed
# @return [Integer]
attr_accessor :speed_avail

#################################################
# The used speed, to be committed
# @return [Integer]
attr_accessor :speed_used

end # class TEZC::Algorithm::Base::Link
##########################################################################


##########################################################################
# A path hop
class Hop

alias inspect to_s

#################################################
# the path number
attr_accessor :path

#################################################
# the node
# @return [Node]
attr_accessor :node

#################################################
# the next hop
# @return [Hop]
attr_accessor :forward

#################################################
# the port
# @return [Integer]
attr_accessor :link

#################################################
# reverse path
# @return [Hash(Hop)] link to prior Hop
attr_accessor :reverse

end # class TEZC::Algorithm::Base::Hop


end # class TEZC::Algorithm::Base

end # module TEZC::Algorithm
end # module TEZC