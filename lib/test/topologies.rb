#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative '../model/runtime'
require_relative '../model/router'
require_relative '../model/buffer'
require_relative '../model/nis'

module TEZC
module Test
  
##########################################################################
# Generate various topologies
#  
class Topologies


##################################################
# new topoplogies generator
# 
# @param sim [Model::Runtime] the simulation runtime
# @param max_levels [Integer] the max number of hierarchical levels
# 
def initialize(sim, max_levels)
   @sim = sim
   @topo_num = 0

   @max_levels = max_levels

   @links = []

end # def initialize()


##################################################
# Add NIS to all routers
# 
# We do this to allow adding extra interfaces
# to standard arrangements.
# 
# @param base_name [String] the base name to use
# 
def add_nis(base_name)
   routers = []
   @sim.items_each(base_name, TEZC::Model::Router) do |rt|
      routers.append(rt)
   end
   routers.each{|rt| rt.nis = Model::NIS.new(rt, 'ni', @max_levels) }

   # set the link hierarchical distances
   @links.each do |rt, pt, lv|
      rt.nis.cfg_distance(pt, lv)
   end
end # def add_nis()


##################################################
# Generate a Clos topology
# 
# For base_name t21, clos_2r = 8, clos_m = 4 this will generate:
# * spine switches named t21s0 thru t21s3
# * edge switches named t21e0 thru t21e7
# * links named t21k0_0 thru t21k7_3, where t21kE_S:
#   - side A is plugged into edge switch E port clos_n+S
#   - side B is plugged into spine switch S port E
#    
# @param base_name [String] the base name to use
# @param clos_n [Integer] number of customer ports per edge switch
# @param clos_2r [Integer] number of edge switches
# @param clos_m [Integer] number of spine switches
# 
def gen_clos_folded(base_name, clos_n, clos_2r, clos_m)
  
   # generate clos_m spine switches each with clos_2r ports
   spine = []
   clos_m.times do |rx|
      rtr = Model::Router.new(@sim, base_name + 's%d' % rx)
      rtr.add_interfaces(clos_2r)
      spine[rx] = rtr
   end
   
   # generate clos_2r edge switches
   #   clos_n open ports
   #   clos_m ports connecting to the spine
   edge = []
   clos_2r.times do |rx|

      # generate the router
      rtr = Model::Router.new(@sim, base_name + 'e%d' % rx)
      rtr.add_interfaces(clos_n + clos_m)
      edge[rx] = rtr

      # generate and plugin clos_m links
      clos_m.times do |lx|
        
         # generate the link
         lnk = Model::Link.new(@sim, base_name + 'k%d_%d' % [rx, lx])
         
         # plug the link in
         rtr.get_iface(clos_n + lx).plugin(lnk.a)
         spine[lx].get_iface(rx).plugin(lnk.b)
      end
      
   end
   
end # def gen_clos_folded()


#################################################
# Generate an specified topology
# 
# @param base_name [String] the base name to use
# @param spec [Hash] the specification
# @return [Integer] the highest hierarchical level
# 
def gen_specified(base_name, spec)

   # base area - we have routers
   if( spec[:routers] )

      # routers are level 0
      level = 0
     
      # start counting routers at 0
      rcnt = 0

      # generate each spec
      spec[:routers].each do |rs|
        
         rspec = rs[:spec]
         
         # generate the routers
         rs[:count].times do |rx|
            rtr = Model::Router.new(@sim, base_name + 'r%d' % rcnt)
            rcnt = rcnt + 1
            rtr.add_interfaces(rspec[:ports])
         end
      end     

   # higher level area, we have areas
   elsif( spec[:areas] )

      # start counting areas at 0
      acnt = 0

      # levels of the sub-areas
      levels = []

      # generate each area
      spec[:areas].each do |ts|
         ts[:count].times do |tx|
            levels[acnt] = gen_specified(base_name + 'a%d' % acnt, ts[:spec])
            acnt = acnt + 1
         end
      end

      level = levels.max

   # nope
   else
      raise "badly formed area specification"
   end

   # add links
   if( spec[:links] )

      # start counting links at 0
      lcnt = 0

      # generate each link
      # nameA, portA, nameB, portB
      spec[:links].each do |ls|

         # generate the link
         lnk = Model::Link.new(@sim, base_name + 'k%d' % lcnt)
         lcnt = lcnt + 1

         # interfaces
         rtA = @sim.item(base_name + ls[0])
         rtB = @sim.item(base_name + ls[2])

         # save the link hierarchical distance
         @links.append( [rtA, ls[1], level] )
         @links.append( [rtB, ls[3], level] )

         # plugin
         rtA.get_iface(ls[1]).plugin(lnk.a)
         rtB.get_iface(ls[3]).plugin(lnk.b)
      end

   end

   # we are one level up
   return level + 1

end # def gen_specified()


end # class TECZ::Test::Topologies

end # module TEZC::Test
end # module TEZC