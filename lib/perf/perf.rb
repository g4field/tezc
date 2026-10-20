#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative '../info/records'
require_relative '../algo/demand'

module TEZC
module Perf
  

##########################################################################
# Pairable Items
module Pairable

attr_accessor :pair_slots

attr_accessor :pairs

#################################################
# New pairable item
def pair_init()
   @pair_slots = 0
   @pairs = []
end # def pair_init()


#################################################
# pair two items
def self.pair_items(itA, itB)

   # sanity check
   if( itA.pair_slots <= 0 || itB.pair_slots <= 0 )
      raise "wtf"
   end

   # add them as pairs
   itA.pairs.push(itB)
   itB.pairs.push(itA)

   # deduct the slots
   itA.pair_slots = itA.pair_slots - 1
   itB.pair_slots = itB.pair_slots - 1

end # def self.pair_items()


#################################################
# create pairs, full mesh
# 
# Note that number of sets and cnt cannot both be odd.
# 
# @param sets [Array(Array)] sets of items to pair
# @param cnt [Integer] number of pairs per set
# @param png [Random] random number generator
# 
def self.pair_mesh(sets, cnt, png)
  
   # sanity check
   sets.each do |st|
      raise "wtf" if( st.map{|it| it.pair_slots}.sum < cnt )
   end
   if( (sets.size % 2) == 1 && (cnt % 2) == 1 )
      raise "wtf"
   end

   # how much to skip
   skip = (sets.size-1).to_f / cnt
   pera = cnt / 2
   mida = (cnt % 2 == 1)
   pera = pera + 1 if( mida )
  
   # make lists of free items
   free_s = sets.map do |st|
      st.select{|it| it.pair_slots != 0}
   end
   remain_s = Array.new(sets.size, cnt)

   # make the pairs
   num_sets = sets.size
   num_sets.times do |ix_a|
      free_a = free_s[ix_a]
      
      # forward pairs
      pera.times do |ix|
         ix_b = (ix_a + 1 + (ix * skip).floor) % num_sets
         raise "wtf" if( ix_b == ix_a )
         free_b = free_s[ix_b]
         
         # the odd last pair only happens on the first half
         next if( mida && ix == pera-1 && ix_a >= num_sets/2 )
              
         # item A
         ixA = png.rand(free_a.size)
         iA = free_a[ixA]

         # item B only one remain or random pick
         ixB = png.rand(free_b.size)
         iB = free_b[ixB]

         # mark as paired
         iA.pairs.push( iB )
         iB.pairs.push( iA )

         # adjust slots and free lists
         if( iA.pair_slots == 1 )
            free_a.delete_at(ixA)
            iA.pair_slots = 0
         else
            iA.pair_slots = iA.pair_slots - 1
         end

         if( iB.pair_slots == 1 )
            free_b.delete_at(ixB)
            iB.pair_slots = 0
         else
            iB.pair_slots = iB.pair_slots - 1
         end

         remain_s[ix_a] = remain_s[ix_a] - 1
         remain_s[ix_b] = remain_s[ix_b] - 1
      end

   end

end # def self.pair_mesh()
  

#################################################
# create pairs, two sets
# 
# @param itemsA [Array] pairable items to pair
# @param itemsB [Array] pairable items to pair
# @param cnt [Integer] how many pairs to create, -1 for all
# @param png [Random] random number generator
# 
def self.pair_two_sets(itemsA, itemsB, cnt, png)
  
   # sanity check
   slotsA = itemsA.map{|it| it.pair_slots}.sum
   slotsB = itemsB.map{|it| it.pair_slots}.sum
   if( (cnt > 0 && (slotsA < cnt || slotsB < cnt)) || # not enough slots
       (cnt < 0 && slotsA != slotsB) ) # doing all and unequal numbers
      raise "wtf"
   end

   # make lists of free items
   free_a = itemsA.select{|it| it.pair_slots != 0}
   free_b = itemsB.select{|it| it.pair_slots != 0}

   # make the pairs
   while( true ) do
     
      # check for completion
      if( cnt > 0 )
         cnt = cnt - 1
      elsif( cnt == 0 || free_a.empty? || free_b.empty? )
         break 
      end

      # item A
      ixA = png.rand(free_a.size)
      iA = free_a[ixA]

      # item B
      ixB = png.rand(free_b.size)
      iB = free_b[ixB]

      # mark as paired
      iA.pairs.push( iB )
      iB.pairs.push( iA )

      # adjust slots and free lists
      if( iA.pair_slots == 1 )
         free_a.delete_at(ixA)
         iA.pair_slots = 0
      else
         iA.pair_slots = iA.pair_slots - 1
      end

      if( iB.pair_slots == 1 )
         free_b.delete_at(ixB)
         iB.pair_slots = 0
      else
         iB.pair_slots = iB.pair_slots - 1
      end

   end

end # def self.pair_two_sets()


#################################################
# create pairs, one set
#  
# @param items [Array] pairable items to pair
# @param cnt [Integer] how many pairs to create, -1 for all
# @param png [Random] random number generator
# 
def self.pair_one_set(items, cnt, png)

   # sanity checks
   slots = items.map{|it| it.pair_slots}.sum
   if( (cnt > 0 && slots < cnt*2) ||  # not enough slots
       (cnt < 0 && slots % 2 == 1 ) ) # doing all and odd number remain
      raise "wtf"
   end

   # make lists of free items
   free_m = items.select{|it| it.pair_slots > 1 }
   free_s = items.select{|it| it.pair_slots == 1 }
   if( free_m.empty? )
      max_slots = 1
   else
      max_slots = free_m.map{|it| it.pair_slots }.max
   end 

   # pair them up
   while( true )
     
      # check for completion
      if( cnt > 0 )
         cnt = cnt - 1
      elsif( cnt == 0 || (free_m.empty? && free_s.empty?) )
         break 
      end

      # number of free items
      free_i = free_m.size + free_s.size

      # near the end, update max_slots
      if( free_i - 2 <= max_slots )
         if( free_m.empty? )
            max_slots = 1
         else
            max_slots = free_m.map{|it| it.pair_slots }.max
         end 
      end
        
      # item A
      # in danger of having no other to pair with, pick one with max_slots
      if( free_i - 1 <= max_slots && max_slots > 1 )
         ixA = free_m.map{|it| it.pair_slots }.index(max_slots)
      else
         ixA = png.rand(free_i)
      end
      if( ixA >= free_m.size )
         iA = free_s[ixA - free_m.size]
      else
         iA = free_m[ixA]
      end

      # item B
      # not allowed to eliminate a single, pick a multiple
      if( free_i - 1 < max_slots && max_slots > 1 )
         ixB = png.rand(free_m.size - 1)
      else
         ixB = png.rand(free_i - 1)
      end
      if( ixA <= ixB )
         ixB = ixB + 1
      end
      if( ixB >= free_m.size )
         iB = free_s[ixB - free_m.size]
      else
         iB = free_m[ixB]
      end
      
      # mark as paired
      iA.pairs.push( iB )
      iB.pairs.push( iA )

      # adjust slots and free lists
      if( iA.pair_slots == 2 )
         free_m.delete_at(ixA)
         free_s.push(iA)
         iA.pair_slots = 1
         ixB = ixB - 1 if( ixB > ixA )
      elsif( iA.pair_slots == 1 )
         free_s.delete_at(ixA - free_m.size)
         iA.pair_slots = 0
         ixB = ixB - 1 if( ixB > ixA )
      else
         iA.pair_slots = iA.pair_slots - 1
      end
      if( iB.pair_slots == 2 )   
         free_m.delete_at(ixB)
         free_s.push(iB)
         iB.pair_slots = 1
      elsif( iB.pair_slots == 1 ) 
         free_s.delete_at(ixB - free_m.size)
         iB.pair_slots = 0
      else
         iB.pair_slots = iB.pair_slots - 1
      end
     
   end

end # def self.pair_one_set()

end # def Pairable


##########################################################################
# A Port
class Port 
include Pairable

#################################################
# new port
def initialize(router, ix)
   @router = router
   @port = ix

   @link = false
   @addr = []
   @node = nil

   pair_init()
   @pair_slots = 1
end # def initialize()

attr_reader :router
attr_reader :port
attr_accessor :link
attr_reader :addr
attr_accessor :node

end # class Port


##########################################################################
# A Customer
class Customer
include Pairable

#################################################
# new customer
def initialize(router, ix)
   @router = router
   @ix = ix

   @addr = []

   pair_init()
end # def initialize()
  
attr_reader :router
attr_reader :ix
attr_reader :addr
  

#################################################
# Create demands from customer pairs
#
# @param area [Area] the area we add demands to
# 
def demands_from_pairs(area, pri, spd)
  
   @pairs.each do |oc|
      id = @router.demand_add
      src = @addr.dup
      dst = oc.addr.dup
      area.demand_add(id, src, dst, pri, spd)
   end
  
end # def demands_from_pairs()


end # def Customer


##########################################################################
# A node
class Node
include Pairable

attr_reader :id

attr_reader :level

attr_reader :ports

attr_reader :customers

end # class Node


##########################################################################
# A Router
class Router < Node

#################################################
# new router
def initialize(rand, numc, nump)
   @id = Info::Records.id_router(rand)
   @level = 0
   @demands = 0

   @ports = Array.new(nump){|pix| Port.new(self, pix) }

   @customers = Array.new(numc){|cix| Customer.new(self, cix) }

   pair_init()
end # def initialize()


#################################################
# aggregate
def aggregate(addr)

   @ports.each do |pt|
      pt.addr.push(addr)
      pt.node = @id
   end

   @customers.each{|cl| cl.addr.push(addr) }

end # def aggregate()
  

#################################################
# add a demand
# 
# @return [String] the demand ID
# 
def demand_add()
   dem = {}
   @demands = @demands + 1
   return Info::Records.id_demand(@id, @demands)
end # def demand_add


end # class Router


##########################################################################
# An Area
class Area < Node

#################################################
# new area
def initialize(nodes)

   @level = nodes[0].level + 1
   
   @nodes = nodes.dup

   # aggregate the nodes
   @nodes.each_index{|nix| @nodes[nix].aggregate(nix+1) }

   @links = []
   @demands = []

   pair_init()
end # def initialize()

attr_reader :nodes
attr_reader :links
attr_reader :demands


#################################################
# Add links from paired ports
def link_pairs(spd)

   # run thru all the nodes
   @nodes.each do |nd|

      # get all the paired ports
      todo = nd.ports.select{|pt| !pt.link && pt.pairs.first }

      # add the links and clean the pair
      todo.each do |pt|
         ptB = pt.pairs.pop
         ptA = ptB.pairs.pop

         # sanity check
         if( pt != ptA || !pt.pairs.empty? || !ptB.pairs.empty? )
            raise "wtf"
         end

         # add the link
         link_add(ptA, ptB, spd)
      end
   end

end # def link_pairs()


#################################################
# Add a link
def link_add(ptY, ptZ, spd)
  
   # sanity check
   if( ptY.addr.size != @level || ptY.link ||
       ptZ.addr.size != @level || ptZ.link )
      raise "wtf"
   end
     
   # new link
   lk = Info::Records::Link.new()
   lk.level = @level
   lk.serial = 2
   lk.speed = spd
   @links.push(lk)

   ptY.link = lk
   ptZ.link = lk

   if( ptY.router.id > ptZ.router.id )
      lk.routerA = ptY.router.id 
      lk.routerB = ptZ.router.id
      lk.portA = ptY.port
      lk.portB = ptZ.port
      lk.nodeA = ptY.node
      lk.nodeB = ptZ.node
      lk.addrA = ptY.addr.dup.freeze
      lk.addrB = ptZ.addr.dup.freeze
   else
      lk.routerA = ptZ.router.id
      lk.routerB = ptY.router.id
      lk.portA = ptZ.port
      lk.portB = ptY.port
      lk.nodeA = ptZ.node
      lk.nodeB = ptY.node
      lk.addrA = ptZ.addr.dup.freeze
      lk.addrB = ptY.addr.dup.freeze
   end
  
end # def link_add()
  

#################################################
# Make demands from customer pairs
def demand_pairs(spd)
   
   # generate demands from customer pairings
   @nodes.each do |nd|
      nd.customers.each do |cs|
     
         # each pair
         cs.pairs.each do |cso|
            id = cs.router.demand_add()
            src = cs.addr.dup
            dst = cso.addr.dup
            pri = 4
            
            demand_add(id, src, dst, pri, spd)
         end
      end
   end
end # def demand_pairs()
  
  
#################################################
# Add a demand
def demand_add(id, src, dst, pri, spd)

   # sanity check
   raise "wtf" if( src.size != dst.size )

   # pass it down
   if( src.last == dst.last && @level > 1 )
      nd = @nodes[src.last-1]
      src.pop
      dst.pop
      nd.demand_add(id, src, dst, pri, spd)
      return
   end

   # record the demand
   dem = {
         id: id,
         src: src.freeze,
         dst: dst.freeze,
         pri: pri,
         spd: spd,
      }

   # a null demand
   if( @level == 1 && src == dst )
      dem[:null] = true
      dem[:fill] = spd
      dem[:hops] = 0
   end

   # save it at our level
   @demands.push( dem )
   
end # demand_add()
  

#################################################
# aggregate
#
# must call with links and demands already created
# from any port and customer pairs.
#
def aggregate(addr)

   # set the ID
   nl = {}
   @links.each do |lr|
      nl[lr.routerA] = true
      nl[lr.routerB] = true
   end
   leader = nl.keys.sort.first
   @id = Info::Records.id_node(leader, @level, 2)

   # process each node
   @ports = []
   @customers = []
   @nodes.each_index do |nix|
      nd = @nodes[nix]

      # free ports
      ndp = nd.ports.select{|pt| !pt.link }
      ndp.each do |pt|
         pt.addr.push(addr)
         pt.node = @id
      end
      @ports.concat(ndp)

      # customers
      ndc = nd.customers
      ndc.each{|cl| cl.addr.push(addr) }
      @customers.concat(ndc)
   end

end # def aggregate()
  

#################################################
# route
def route(algo)

   dems_fc = {}
   dems = []
   @demands.each do |dem|

      # skip null demands
      next if( dem[:null] )

      # create the list of demands
      dr = TEZC::Algorithm::Demand.new
      dr.id = dem[:id]
      dr.original = (dem[:pri] != 7)
      dr.priority = dem[:pri]
      dr.source = dem[:src]
      dr.destination = dem[:dst]
      dr.speed = dem[:spd]
      dems.push(dr)

      # sort demands by fill match criteria (pri, src, dst node)
      fc = [dem[:pri], dem[:dst].last] + dem[:src]
      ary = dems_fc[fc]
      if( !ary )
         ary = []
         dems_fc[fc] = ary
      end
      ary.push( dem )

      # default is no traffic allowed, 0 hops
      dem[:fill] = 0
      dem[:hops] = 0
   end

   # print status
   #puts "\n\nRouting level %d\n\tDemands: %d\n\tLinks: %d" %
   #   [ @level, dems.size, @links.size ]

   # call the algorithm
   data = {
      level: @level,
      links: @links,
      demands: dems,
      fills: {},
      paths: {},
   }
   results = algo.route(data)
   paths = results[:paths]
   fills = results[:fills]

   #####################
   # review the fills
   fills.each_pair do |num, rf|

      # the path
      rp = paths[rf.path]

      # frac filled
      frac = rf.speed.to_f / rf.speed_request

      # get the pertinent demands
      fc = [rf.priority, rf.destination] + rf.source
      dems_fill = dems_fc[fc]

      # find first link
      lix = 0
      nix_c = rf.source.last
      while( rp.link[lix].addr_orig.last != nix_c )
         lix = lix + 1
      end
      hops = rp.link.size - lix

      # mark demands with the fraction filled and number of hops
      dems_fill.each do |dem|
        dem[:fill] = (dem[:spd] * frac).floor
        dem[:hops] = hops
      end

      # no derivative demands at base level
      next if( @level <= 1 )

      # start at source of demand
      src = rf.source.dup
      
      ################
      # source and transit nodes
      while( rp.link[lix] )

         # node
         nix_c = src.last
         nd_d = @nodes[nix_c-1]

         # destination
         dst = rp.link[lix].addr_orig.dup

         # they are in the same node
         src.pop
         dst.pop

         # all the demands covered by this fill
         dems_fill.each do |dem|
            nd_d.demand_add(dem[:id], src.dup, dst.dup, 7, dem[:fill] )
         end

         # next source is the termination of link
         src = rp.link[lix].addr_term.dup
         lix = lix + 1
      end

      ###############
      # exit node

      # node
      nix_c = src.last
      nd_d = @nodes[nix_c-1]
      src.pop

      # demand from last link to destination
      dems_fill.each do |dem|
         dst = dem[:dst].dup
         dst.pop
         
         nd_d.demand_add(dem[:id], src.dup, dst.dup, 7, dem[:fill] )
      end

   end

   # add up stats
   st_nul_o = 0
   st_req_o = 0
   st_fil_o = 0
   st_nul_d = 0
   st_req_d = 0
   st_fil_d = 0
   @demands.each do |dem|
      if( dem[:pri] == 7 )
         if( dem[:null] )
            st_nul_d = st_nul_d + dem[:spd]
         else
            st_req_d = st_req_d + dem[:spd]
            st_fil_d = st_fil_d + dem[:fill]
         end
      else
         if( dem[:null] )
            st_nul_o = st_nul_o + dem[:spd]
         else
            st_req_o = st_req_o + dem[:spd]
            st_fil_o = st_fil_o + dem[:fill]
         end
      end
   end
   @stats = {
      original_null: st_nul_o,
      original_req: st_req_o,
      original_fill: st_fil_o,
      derivative_null: st_nul_d,
      derivative_req: st_req_d,
      derivative_fill: st_fil_d,
   }

   # print the stats
   #st_pct_o = (st_fil_o == 0) ? 1.0 : st_fil_o.to_f / st_req_o
   #st_pct_d = (st_fil_d == 0) ? 1.0 : st_fil_d.to_f / st_req_d
   #puts "\n\tOriginal: %d pct %0.5f\n\tDerivative %d pct %0.5f\n" %
   #   [ st_req_o, st_pct_o,
   #     st_req_d, st_pct_d ]

   # recurse
   return if( @level <= 1 )
   @nodes.each_index do |nix|
      nd = @nodes[nix]
      nd.route(algo)
   end

end # def route

end # class Area

end # module TEZC::Perf
end # module TEZC