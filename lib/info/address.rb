#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'

module TEZC
module Info

##########################################################################
# Module which tracks the router address and nodes
# 
class Address < Mod
  

#################################################
# new module
def initialize(nis)
  
   # save the service
   super(nis)

   # our address and node
   @addr = Array.new(@nis.max_levels, 0)
   @oldaddr = Array.new(@nis.max_levels, 0)
   @node = Array.new(@nis.max_levels)
   @used = 0

   # register for triggers
   [  :db_link_update,
      :db_area,
      :db_addr_update,
   ].each{|trig| @nis.trigger_register(trig, 0, self) }

   # base level node ID is the router ID
   @node[0] = @nis.id

end # def initialize()
  

#################################################
# the address of the router
# @return [Array(Integer)]
attr_reader :addr

#################################################
# the old address of the router
# @return [Array(Integer)]
attr_reader :oldaddr

#################################################
# the node IDs
# @return [Array(String)]
attr_reader :node

#################################################
# what hierarchichal levels are used in the network
# @return [Integer]
attr_reader :used


#################################################
# Address is stable
def stable?
   return ( @used != 0 && !@addr.first(@used).any?(0) )
end # def stable?


#################################################
# Distance to a given address
#
# @param oth [Array(Integer)] the other address
# @return [Integer] distance or -1 if unknown
#
def distance(oth)

   dist = @used

   while( dist > 0 )
      dist = dist - 1

      if( @addr[dist] == 0 || oth[dist] == 0 )
         return -1
      elsif( @addr[dist] != oth[dist] )
         return dist
      end
   end

   return -1

end # def distance()


#################################################
# (see Mod#trigger )
def trigger(trig, level, data)

   case trig
     
   # a link update
   when :db_link_update
      @used = [@used, level].max

   # an area descriptor
   when :db_area
      ad = data

      # if we change the area leader ID or partition number
      # this changes the node ID of the next level up
      if(   level < @nis.max_levels && (
            ad[:leader] != ad[:prev][:leader] ||
            ad[:partition] != ad[:prev][:partition] ))
         @node[level] = Records.id_node(ad[:leader], level, ad[:partition])
         @nis.trigger(:self_node, level+1, @node[level])
      end

   # an address update
   when :db_addr_update
      aa = data

      # if this is our node, check if the address changes
      if( aa.node == @node[level-1] &&
            aa.addr != @addr[level-1] && aa.addr != 0 )
         @oldaddr[level-1] = @addr[level-1]
         @addr[level-1] = aa.addr
         @nis.trigger(:self_address, level, aa.addr)
      end

   # unknown
   else
      raise "Unknown trigger received"
   end

   # we do not do anything complicated
   return {}

end # def trigger()
  

end # class TEZC::Info::Address
  
end # module TEZC::Info
  
end # module TEZC
