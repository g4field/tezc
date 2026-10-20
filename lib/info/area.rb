#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'
require_relative 'records'

module TEZC
module Info

##########################################################################
# Area Controller Module
#
# The Area controller does two things.
# First, tells the database when to become the area leader.
# Second, assigns addresses.
# 
# To do this, it maintains a model of the nodes and links in the area,
# and uses it to detect splits, nodes without addresses, etc.
# 
# An area is considered split when:
# 1) a link is removed and there are node(s) not reachable,
# 2) after links settle there are node(s) not reachable.
# The first and second are when a link loss splits the area into fractions,
# the second should never happen but ensures eventual consistency.
# 
class Area < Mod


#################################################
# New controller module
#
# @param nis (see Mod#initialize)
# @param level [Integer] the area level
#
def initialize(nis, level)
   super(nis)

   @level = level

   # state
   @stable = false
   
   # times
   @time = {
      start: @nis.now,
      stable: 1,
      area: 1,
      leader: 1,
      link: 1,
   }

   # model of the area
   @node = Hash.new
   @link = Hash.new
   @check = {
      model: true,
      addrs: false,
   }
   @leader = nil
   @final = false

   # results of examining the model
   @reachable = 0
   @routers = {}

   # address assignments
   @addr = Hash.new 
   @addr_place = 0
   @addr_needed = Hash.new

   # register to receive triggers
   [  :db_area,
      :db_link_update,
      :db_link_remove,
      :db_addr_update,
   ].each{|trig| @nis.trigger_register(trig, @level, self) }

   # configuration
   @cfg_addr_max = 254           # maximum address
   @cfg_start = 10 * 1000        # wait at startup
   @cfg_mult = 250               # wait for higher priority router
   @cfg_start_mult = 5000        # multiple at startup
   @cfg_refresh = 15 * 1000      # refresh leader
   @cfg_expire = 20 * 1000       # expire without hearing from the leader
   @cfg_inactive = 3 * 1000      # expire if the leader does not respond
   @cfg_stable = 250             # time to wait for DB to settle before action

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

end # def initialize()


#################################################
# (see Mod#trigger )
def trigger(trig, level, data)

   # sanity chek
   raise "Trigger for wrong level" if( level != @level )
   
   case trig
   
   # the area changes
   when :db_area
      model_area(data)

   # the link update
   when :db_link_update
      model_update(data)

   # the link removal
   when :db_link_remove
      model_remove(data)

   # the address assignment
   when :db_addr_update
      model_addr(data)

   else
      raise "Unknown trigger received"
   end
   
   # check all the stuff and adjust the timer
   check_stuff()
   
end # def trigger()


#################################################
# (see Mod#timer)
def timer()
  
   case @reason
        
   # we might be stable
   when :stable

      # check the database change
      if( @nis.db.time_change + @cfg_stable <= @nis.now )
         @time[:stable] = @nis.now
         @stable = true
      end
   
   # assign addresses
   when :address
      log(:verbose, "Area %d assigning addresses nodes %d links %d" %
         [@level, @node.size, @link.size])
      
      # all nodes without addresses
      @addr_needed.each_value do |nd|
         addr_assign(nd)
      end
      @addr_needed = {}

   # refresh
   when :refresh
      log(:verbose, "Area %d refresh" % [@level])

      # assign address zero again
      ada = addr_info(0)
      ada[:serial] = ada[:serial] + 1
      addr_send(ada)

   # inactive
   when :inactive, :split, :start
      log(:info, "Area %d assume leadership %s %s %s" % 
         [@level, @nis.id, @reason,
         @place ? @place.to_s : '-'])

      # tell the database we are the leader
      if( @reason == :split )
         log(:info, "Area %d split reach %d nd %d lk %d" % 
            [@level, @reachable, @node.size, @link.size])

         @nis.db.leader(@level, @reachable+1, true)
      else
         @nis.db.leader(@level, 1, false)
      end

      # set address zero
      ada = addr_info(0)
      ada[:serial] = ada[:serial] + 1
      ada[:dropped] = false
      ada[:node] = @nis.address.node[@level-1]
      addr_send(ada)

   else
      raise "Unknown area timer reason"
   end

   # check all the stuff and adjust the timer
   check_stuff()

end # def timer()


###########################################################
###########################################################
# Check stuff


#################################################
# Check things
#
def check_stuff()
    
   # wait until we are stable
   if( !@stable )
      @reason = :stable
      @expire = [
         @time[:start] + @cfg_start,
         @time[:area] + @cfg_stable,
         @nis.db.time_change + @cfg_stable,
      ].max

      # set the timer
      @timer.expires = @expire
      @nis.timer_set(@timer)
      return
   end
  
   #####################
   # run checks

   if( @check[:model] )
      check_model()
      check_place()
      @check[:model] = false
   end

   if( @check[:addrs] )
      @addr_needed = @node.select{|id,nd| !nd[:addr] }
      @check[:addrs] = false
   end

   #####################
   # calculate timeout

   # we are the leader
   if( @nis.db.area[@level-1][:leader] == @nis.id )

      # split
      if( @reachable != @node.size )
         @reason = :split
         @expire = @nis.now

      # addresses
      elsif( !@addr_needed.empty? )
         @reason = :address
         @expire = @nis.now

      # refresh
      else
         @reason = :refresh
         @expire = @time[:leader] + @cfg_refresh
      end

   # no place
   elsif( !@place )
      @reason = :noplace
      @expire = nil

   # at startup
   elsif( !@nis.db.area[@level-1][:leader] )
      @reason = :start
      @expire = @time[:stable] + (@cfg_start_mult * @place)

   # split
   elsif( @reachable != @node.size )
      @reason = :split
      @expire = [@time[:stable], @time[:link]].max + (@cfg_mult * @place)

   # inactive
   else
      @reason = :inactive
      arr = [ @time[:leader] + @cfg_expire ]

      # address required, inactive delay
      if( !@addr_needed.empty? )
         arr.push( [@time[:stable], @time[:leader]].max + @cfg_inactive )
      end
      @expire = arr.min + (@cfg_mult * @place)
   end

   # set the timer
   @timer.expires = @expire
   if( @timer.expires )
      @nis.timer_set(@timer)
   else
      @nis.timer_del(@timer)
   end

end # def check_stuff()


#################################################
# Check the model
# 
def check_model()

   # clear all found markers
   @node.each_value{|nd| nd[:found] = false }

   # no node or link is reachable
   reach_node = {}
   reach_link = {}

   # start at our node
   found = []
   me = @node[@nis.address.node[@level-1]]
   found.push(me) if( me )

   # run the BFS
   found.each do |nd|
      reach_node[nd[:id]] = true
      nd[:edge].each_pair do |adj_id, adj_links|
         adj_links.each{|lid| reach_link[lid] = true }
         adj = @node[adj_id]
         next if( adj[:found] )
         adj[:found] = true
         found.push(adj)
      end
   end
      
   # save how many reachable nodes we have
   @reachable = reach_node.size

   # routers connected to reachable links are reachable
   @routers = {}
   reach_link.each_key do |lid|
      lr = @link[lid]
      @routers[lr.routerA] = true
      @routers[lr.routerB] = true
   end

end # def check_model()


#################################################
# Check our place for assuming leadership
#
def check_place()

   # calculate our election place
   if( @routers.empty? )

      # if we were the router on the last link removed, become the leader
      if( @final ) 
         @place = 0

      # or in a worst case, the first 4 bits of our ID plus a base of 2
      else
         @place = 2 + @nis.id[0,1].to_i(16)
      end
      
   # our election place is based on reachable routers
   else
      @place = @routers.keys.sort.index(@nis.id)
   end

end # def check_place()



###########################################################
###########################################################
# address stuff

#################################################
# Assign an address to a node
# 
def addr_assign(nd)

   # find a link that has an existing address
   ad = nil
   nd[:edge].values.flatten(1).each do |lid|
      ld = @link[lid]
      lkary = ( ld.nodeA == nd[:id] ) ? ld.addrA : ld.addrB
      lkaddr = lkary[@level-1]
      next if( lkaddr == 0 )
      if( addr_avail(lkaddr) )
         ad = lkaddr
         break
      end
   end

   # find an address by trying one at a time
   if( !ad )
      adp = (@addr_place == @cfg_addr_max) ? 1 : @addr_place + 1
      while( adp != @addr_place )
         if( addr_avail(adp) )
            ad = adp
            break
         end
         adp = (adp == @cfg_addr_max) ? 1 : adp + 1
      end

      # keep track of last one we assigned this way
      if( ad )
         @addr_place = ad
      end
   end

   # no address is available
   if( !ad )
      log(:error, "Area %d address: none available" % [@level] )
      return
   end

   # log
   log(:verbose, "Area %d assign address %s %d" % [
         @level, nd[:id], ad])

   # set and send the address
   ada = addr_info(ad)
   if( ada[:node] != nd[:id] )
      ada[:node] = nd[:id]
      ada[:serial] = ada[:serial] + 1
   end
   ada[:dropped] = false

   addr_send(ada)
end # def addr_assign()


#################################################
# Get an address info
def addr_info(ad)
  
   ada = @addr[ad]
   if( !ada )
      ada = {
         addr: ad,
         id: Records.id_addr(@nis.id, @level, ad),
         serial: 0,
      }
      @addr[ad] = ada
   end

   return ada
end # def addr_info()
  

#################################################
# Send the address to the database
def addr_send(ada) 
  
   # add it to the database
   adb = Records::Addr.new
   adb.id = ada[:id]
   adb.level = @level
   adb.serial = ada[:serial]
   adb.area = @nis.id
   adb.addr = ada[:addr]
   adb.node = ada[:node]
   @nis.db.update(adb, :election)

end # def addr_send()


#################################################
# Check if an address is available
# 
def addr_avail(ad)

   # is there already an assignment?
   ada = @addr[ad]
   return true if( !ada )

   # has the assignment been dropped?
   return ada[:dropped]

end # def addr_avail()


###########################################################
###########################################################
# Model changes

#################################################
# Updates to the area
#
# @param ad [Hash] area data (:leader, :election, :partition, :prev)
# 
def model_area(ad)

   # what changed?
   cng_leader = ( ad[:leader] != ad[:prev][:leader] )
   cng_partition = ( ad[:partition] != ad[:prev][:partition] )
   cng_election = ( ad[:election] != ad[:prev][:election] )
  
   # log
   if( cng_leader )
      if( ad[:prev][:leader] == @nis.id )
         log(:info, "Area %d change leader %s (lost)" %
            [@level, ad[:leader]])
      else
         log(:verbose, "Area %d change leader %s" %
            [@level, ad[:leader]])
      end
   end
   if( cng_partition )
      log(:verbose, "Area %d change partition %d" % [@level, ad[:partition]])
   end
   if( cng_election )
      log(:verbose, "Area %d change election %d" % [@level, ad[:election]])
   end

   # leader changed
   if( cng_leader )
      @leader = nil
   end

   # partition changes - links were dropped
   if( cng_partition )
      @link = {}
      @node = {}
      @check[:model] = true
   end

   # election changes - addresses were dropped
   if( cng_election )
      @node.each_value{|nd| nd[:addr] = nil }
      @addr.each_value{|ar| ar[:dropped] = true }
      @check[:addrs] = true
   end

   # clear the final link flag
   @final = false

   # we have heard from the leader
   @time[:leader]= @nis.now

   # begin unstable time
   @stable = false
   @time[:area] = @nis.now

end # model_area()


#################################################
# Update a link
# 
# @param lr [Records::Link] the link record
# 
def model_update(lr)

   # log
   #log(:verbose, "Area %d link update %s %d" % 
   #      [@level, lr.id, lr.serial])

   log(:debug, "Area %d link update %s %d nd %s-%s ad %s-%s" % 
         [@level, lr.id, lr.serial,
         lr.nodeA ? lr.nodeA : '-',
         lr.nodeB ? lr.nodeB : '-',
         lr.addrA.inspect,
         lr.addrB.inspect])

   # update the time
   @time[:link] = @nis.now

   # not stable
   @stable = false

   # save it
   lro = @link[lr.id]
   @link[lr.id] = lr.dup
 
   # no change to the model
   if( !lr.nodeA || !lr.nodeB || (
         lro && 
         lr.routerA == lro.routerA &&
         lr.routerB == lro.routerB &&
         lr.nodeA == lro.nodeA &&
         lr.nodeB == lro.nodeB ) )
      return
   end

   # it will need to be checked
   @check[:model] = true

   # remove the old link
   if( lro && lro.nodeA && lro.nodeB )

      # the link is between the same routers
      rsame = (lr.routerA == lro.routerA && lr.routerB == lro.routerB)
     
      # update the edge
      [  [lro.nodeA, lro.nodeB],
         [lro.nodeB, lro.nodeA] ].each do |idA, idB|
      
         nd = @node[idA]

         # delete the link from the edge
         lk = nd[:edge][idB]
         lk.delete(lro.id)

         # delete the edge if no more links
         nd[:edge].delete(idB) if( lk.empty? )
           
         # delete the node if no more edges and it was the same routers
         if( nd[:edge].empty? && rsame )
            @node.delete(idA)

            # drop the address assignment, if any
            if( nd[:addr] )
               ada = @addr[nd[:addr]]
               ada[:dropped] = true if( ada )     
            end
         end

      end
   end

   # add the new link
   [  [lr.nodeA, lr.nodeB],
      [lr.nodeB, lr.nodeA] ].each do |idA, idB|
   
      # get the node, adding if needed
      nd = model_node(idA)

      # add the link to the edge
      lk = nd[:edge][idB]
      if( !lk )
         lk = []
         nd[:edge][idB] = lk
      end
      lk.push(lr.id)
   end
  
end # def model_update()


#################################################
# Remove a link
#
# @param lr [Records::Link] the link record
# 
def model_remove(lr)

   # log
   log(:verbose, "Area %d link remove %s %d" % 
         [@level, lr.id, lr.serial])

   # update the time
   @time[:link] = @nis.now

   # get the link
   lro = @link[lr.id]
   return if( !lro )

   # remove it from the link list
   @link.delete(lr.id)

   # this changes the model
   @check[:model] = true

   # update the edge
   [  [lro.nodeA, lro.nodeB],
      [lro.nodeB, lro.nodeA] ].each do |idA, idB|
   
      nd = @node[idA]

      # delete the link from the edge
      lk = nd[:edge][idB]
      lk.delete(lro.id)

      # delete the edge if no more links
      nd[:edge].delete(idB) if( lk.empty? )

   end

   # record the last link removed for use in single node situation
   @final = ( lr.routerA == @nis.id || lr.routerB == @nis.id )
   
end # def model_remove()


#################################################
# Add an address to the model
# 
# @param ar [Records::Address] the address record
# 
def model_addr(ar)

   # leader node
   if( ar.addr == 0 )
      log(:verbose, "Area %d leader node %s" % 
         [@level, ar.node])

      # save it
      @leader = ar.node
      
   # normal address
   else
      log(:verbose, "Area %d address update %s %d" % 
         [@level, ar.node, ar.addr])

      # the addresses have changed
      @check[:addrs] = true

      # store the address
      nd = model_node(ar.node)
      nd[:addr] = ar.addr
   end

   # we have heard from the leader
   @time[:leader]= @nis.now
  
end # def model_addr()


#################################################
# Get a node, adding to the model if necessary
#
# @param nid [String] the node ID
# @return [Hash] the node hash
# 
def model_node(nid)
   nd = @node[nid]
   if( !nd )
      nd = { id: nid, edge: {} }
      @node[nid] = nd
      @check[:addrs] = true
   end
   return nd
end # def model_node()


end # class TEZC::Info::Area

end # module TEZC::Info
end # module TEZC