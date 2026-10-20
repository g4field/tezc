#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'base'

module TEZC
module Algorithm

##########################################################################
# Avoid Congestion algorithm
#
# This algorithm is a modified BFS shortest hop count algorithm.
# It attempts to avoid congestion on links by trading extra hops for lower
# congestion.
# Congestion is measured as the total requested traffic over a link
# divided by the link speed.
# The algorithm works by doing a BFS exploration of the network for each
# demand at a priority level.
# * Start at the source with 0 hops and 0 congestion.
# * Evaluate each link and calculate the hops and congestions to reach
#   the adjacent node.
# * If the calculated congestion is smaller than all equal/shorter current
#   potential paths, and the hop count is less than the shortest path + N,
#   record the link as a potential path.
# * Once the destination is found, continue to process paths for N more hops.
# * Pick the path with the smallest max congestion.
# After all demands at a given priority level have been processed, determine
# filled speeds:
# * Demands get maximum of
# * All demands using a link are allocated a fair share.
#   Congestion is total requested speed divided by link speed.
#   Links get min(1/cong, 1) times their request.
# * Re-score the links, and continue to next link.
# Fix the link utilization and evaluate the next priority level.
#
class AvoidCong < Base


#################################################
# New algorithm
def initialize(file, extend=2)
   super(file)

   @extend = extend

   @link_class = Link
   @node_class = Node
end # def initialize()


#################################################
# Route a priority level
# 
# @param lv [Integer] the priority level
# 
def route_priority(lv)

   # track the prior link usage
   @links.each do |lk|
      lk.speed_prior = lk.speed_used
   end

   # place all demands
   @demands[lv].each do |dm|
     
      # try to place it
      dm.links = route_demand(dm)

      # not placed
      next if( !dm.links )
        
      # add it to the links
      trail_add(dm)
   end

   # calculate congestion on all links
   @links.each do |lk|
      if( lk.speed_used == lk.speed_prior )
         lk.congest = -1.0
      else
         frac = (lk.speed_used - lk.speed_prior).to_f / lk.speed_avail
         lk.congest = [frac, 1.0].max
      end
   end

   # calculate fills, take worst congestion of all links
   @demands[lv].each do |dm|
      next if( !dm.links )
      cong = dm.links.map{|lk| lk.congest}
      if( cong.min < 0 ) # a link is completely used
         dm.fill = 0
      else
         dm.fill = (dm.speed.to_f / cong.max).floor
      end
   end

   # adjust how much is used on each link
   @links.each do |lk|
      lk.speed_used = lk.demands.values.map{|dm| dm.fill}.sum
   end

end # def route_priority()


#################################################
# Route a demand
# 
# @param dm [Demand] the demand to route
# @return [Array,nil] links from dest to source
#   or nil if not routable
#   
def route_demand(dm)

   # clear our work
   @nodes.each_pair do |ad, nd|
      nd.dist = nil
      nd.trail = Array.new(@extend, nil)
      nd.congest = Array.new(@extend, nil)
   end

   # start at the source
   nd = @nodes[dm.src]
   return nil if( !nd )
   nd.dist = 0
   nd.congest[0] = 0.0
   nxt_level = [nd]
   dist = 0
   dist_dest = nil

   # stop when there are no more nodes to explore
   # only run @extend hops beyond the destination
   while(   !nxt_level.empty? &&
            (!dist_dest || dist <= dist_dest + @extend) )

      cur_level = nxt_level
      nxt_level = []

      # each node at this distance
      cur_level.each do |nd|
        
         # index of the path for this node
         nd_ix = dist - nd.dist
         nd_cong = nd.congest[nd_ix]

         # check each outbound link
         nd.link_ob.each do |lk|
            aj = lk.node_ib

            # index of the path for the adjacent node
            if( aj.dist )
               aj_ix = dist - aj.dist + 1
               next if( aj_ix >= @extend )
            else
               if( aj.addr == dm.dst )
                  dist_dest = dist + 1
               end
               aj.dist = dist + 1
               aj_ix = 0
            end

            # the congestion
            aj_cong = aj.congest.first(aj_ix+1).compact.min
            lk_cong = (lk.speed_used + dm.speed - lk.speed_prior).to_f / lk.speed_avail
            cong = [lk_cong, nd_cong].max       

            # this is the best option for the distance
            if( !aj_cong || cong < aj_cong )
               if( !aj.congest[aj_ix] )
                  nxt_level.push( aj )
               end
               aj.congest[aj_ix] = cong
               aj.trail[aj_ix] = lk
            end
         end
      end

      # increase the distance
      dist = dist + 1
   end

   # did not find the destination
   return nil if( !dist_dest )

   # walk the trail backwards
   # start at the dest
   list = []
   nd = @nodes[dm.dst]
   dist = nd.dist + nd.congest.index(nd.congest.compact.min)
   while( dist > 0 )
      ix = dist - nd.dist
      lk = nd.trail[ix]
      list.push(lk)
      nd = lk.node_ob
      dist = dist - 1
   end
   if( nd.addr != dm.src )
      raise "routing is very broken!"
   end
   return list

end # def route_demand()


#################################################
# Add a trail to the links
def trail_add(dm)
   dm.links.each do |lk|
      lk.demands[dm.num] = dm
      lk.speed_used = lk.speed_used + dm.speed
   end
end # def trail_add()



##########################################################################
# A node
class Node < Base::Node


#################################################
# The distance
# @return [Integer]
attr_accessor :dist

#################################################
# 
attr_accessor :congest


#################################################
#
attr_accessor :trail


end # class TEZC::Algorithm::AvoidCong::Node


##########################################################################
# A link
class Link < Base::Link


#################################################
# New link
def initialize()
   @demands = {}
end # def initialize()


#################################################
# the demands using this link
# @return [Hash] number to {Demand}
attr_accessor :demands

#################################################
# the speed used by higher priority
attr_accessor :speed_prior

#################################################
# the congestion
# @return [Float] 
attr_accessor :congest

end # class TEZC::Algorithm::AvoidCong::Link


end # class TEZC::Algorithm::AvoidCong

end # module TEZC::Algorithm
end # module TEZC