#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'
require_relative 'records'

module TEZC
module Info

##########################################################################
# Handle routes
#
# Takes updates to route info and inserts appropriate rules into the router.
#
class Routes < Mod


#################################################
# New Routes module
# 
# @param nis [Service] the NIS
# 
def initialize(nis)

   # save self info
   super(nis)

   # what we have installed
   @addrs_info = Array.new(@nis.max_levels){ Hash.new }
   @fills_info = Array.new(@nis.max_levels){ Hash.new }
   @paths_info = Array.new(@nis.max_levels){ Hash.new }
   @ingrs_info = Hash.new

   # the todo lists
   @todo_install = Array.new
   @todo_remove = Array.new
   @todo_ingress = Array.new

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

   # register for triggers
   [  :stable_install
   ].each{|trig| @nis.trigger_register(trig, 0, self)}

end # def initialize()


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig

   when :stable_install

      # we had better be done
      if( !@todo_remove.empty? || !@todo_remove.empty? )
         raise "Did not finish installing routes before starting again!"
      end
    
      # process each level
      @nis.max_levels.times do |ix|
         make_todo_level(ix+1)
      end

      # then process ingress
      make_todo_ingress()

      # log
      log(:verbose, "Routes starting update")

   else
      raise "Unknown trigger received"
   end

   # run in timer()
   @timer.expires = @nis.now - 1
   @nis.timer_set(@timer)

end # def trigger()


#################################################
# (see Mod#timer)
def timer()

   # remove any remaining items
   info = @todo_remove.pop
   if( info )
      do_remove(info)

      @timer.expires = @nis.now - 1
      @nis.timer_set(@timer)
      return
   end

   # install any remaining items
   info = @todo_install.pop
   if( info )
      do_install(info)

      @timer.expires = @nis.now - 1
      @nis.timer_set(@timer)
      return
   end

   # process any ingress changes
   info = @todo_ingress.pop
   if( info )
      do_ingress(info)

      @timer.expires = @nis.now - 1
      @nis.timer_set(@timer)
      return
   end

   # nothing left to do
   log(:verbose, "Routes finished update")
   @nis.timer_del(@timer)

end # def timer()


################################################################
# Private
private


#################################################
# Make a list of actions for a level
def make_todo_level(lev)
  
   #####################
   # address
   
   # installed
   addr_inst = []
   info = nil
   lev.times do |ix|
      info = @addrs_info[ix]
      if( info[:installed] )
         addr_inst[ix] = info[:installed][:value]
      else
         addr_inst[ix] = 0
      end
   end

   # current
   addr = @nis.address.addr.first(lev)
   info[:current] = { value: @nis.address.addr[lev-1] }

   # no change
   addr_same = ( addr.last == addr_inst.last )

   # add todo
   if( !addr_same )

      # install
      if( addr.last != 0 )
         ary = []
         8.times do |pri|
            dst = Records.label_node(lev, pri, addr.last)
            ary.append( [dst, :pop, nil ] )
         end
         info[:current][:rule_list] = ary
         @todo_install.append( info )
      end

      # remove
      if( addr_inst.last != 0 )
         @todo_remove.append( info )
      end

   end

   ################
   # paths
    
   paths = @paths_info[lev-1]
   paths.each_value{|it| it.delete(:current) }

   # current
   @nis.db.each(lev, :path) do |rp|
      info = paths[rp.path]
      if( !info )
         info = {}
         paths[rp.path] = info
      end
      info[:current] = {
         db: rp,
         value: {
            id: rp.id,
            serial: rp.serial
         },
      }
   end

   # make todo
   paths.each_pair do |num, info|
      
      ins = info[:installed]
      cur = info[:current]

      # same values, no action
      next if( addr_same && ins && cur &&
            cur[:value][:id] == ins[:value][:id] &&
            cur[:value][:serial] == ins[:value][:serial]  )

      # remove installed
      if( ins )
         @todo_remove.append( info )
      end

      # install current
      if( cur )
         @todo_install.append( info )
         cur[:rule] = rule_path(lev, addr, cur[:db])
      end
   end
   
   #####################
   # fills
   
   fills = @fills_info[lev-1]
   fills.each_value{|it| it.delete(:current) }

   # current
   @nis.db.each(lev, :fill) do |rf|
      info = fills[rf.demand]
      if( !info )
         info = {}
         fills[rf.demand] = info
      end
      info[:current] = {
         db: rf,
         value: {
            id: rf.id,
            serial: rf.serial,
         },
      }
   end

   # make todo
   fills.each_pair do |num, info|
      
      ins = info[:installed]
      cur = info[:current]

      # same values, no action
      next if( addr_same && ins && cur &&
            cur[:value][:id] == ins[:value][:id] &&
            cur[:value][:serial] == ins[:value][:serial]  )

      # remove installed
      if( ins )
         @todo_remove.append( info )
      end

      # install current
      if( cur )
         @todo_install.append( info )

         pnum = cur[:db].path
         pinf = paths[pnum]
         if( !pinf || !pinf[:current] )
            log(:error, "Missing path %d" % pnum)
            cur[:rule] = nil
         else
            cur[:rule] = rule_fill(lev, addr, cur[:db], pinf[:current][:db])
         end
      end
   end


   #####################
   # clean up
   
   # database items not needed for paths, fills get examined by ingress
   paths.each_pair do |num, info|
      if( info[:current] )
         info[:current].delete(:db)
      end
   end

   # how much work did we do?
   total = (fills.size + paths.size) / 1000
   if( total > 0 )
      @nis.activity(:general, total)
   end

end # def make_todo_level()


#################################################
# Make a list of actions for ingress
def make_todo_ingress()

   # clear out anything we don't have installed
   @ingrs_info.delete_if{|num, ii| !ii[:installed] }

   # sort current demands by level, destination
   ingr = Array.new(@nis.max_levels){ Hash.new }
   @nis.demands.local.each_value do |dm|
   
      # ignore ingress demands that don't have a Demand
      next if( dm[:level] == 0 )
     
      # by level
      lev = ingr[dm[:level]-1]
      
      # by destination
      dst = lev[dm[:dest].last]
      if( !dst )
         dst = []
         lev[dm[:dest].last] = dst
      end

      # append it
      dst.append( dm )

      # make sure we have info for this item
      ii = @ingrs_info[dm[:num]]
      if( !ii )
         ii = { num: dm[:num] }
         @ingrs_info[dm[:num]] = ii
      end
      ii[:current] = { serial: dm[:serial] }
   end

   # process each level
   @nis.max_levels.times do |ix|
      
      fills = @fills_info[ix]
      ingr_lev = ingr[ix]
      addr = @nis.address.addr.first(ix+1)

      fills.each_pair do |num, info|
         cur = info[:current]
         next if( !cur )

         # only care about Fills with our source address
         if( cur[:db].source != addr )
            cur.delete(:db)
            next
         end

         # only care about Fills that match local ingress demands
         ingr_list = ingr_lev[cur[:db].destination]
         next if( !ingr_list )

         # calc the fill rate and clean up the database record
         max = cur[:db].speed
         dem_total = cur[:db].speed_request
         rate = max.to_f / cur[:db].speed_request.to_f
         cur.delete(:db)

         # total ingress demands
         total = ingr_list.map{|dm| dm[:speed] }.sum
         if( total > dem_total )
            log(:error, "Fill indicates lower demands than ingress demands %d %d" %
                  [total, dem_total])
            next
         end
         
         # record the filled ingress demands
         ingr_list.each do |dm|
            @ingrs_info[dm[:num]][:current][:fill] = (dm[:speed] * rate).floor
         end
      end
   end

   # make the todo list
   @todo_ingress = []
   @ingrs_info.each_pair do |num, ii|
      # no change
      if( ii[:current] && ii[:installed] &&
            ii[:current][:serial] == ii[:installed][:serial] &&
            ii[:current][:fill] == ii[:installed][:fill] )
         ii.delete(:current)
         next
      end
      
      # update
      @todo_ingress.append( ii )
   end

end # def make_todo_ingress()


#################################################
# Get the rule for a Path
# 
# @param lev [Integer] the level
# @param addr [Array(Integer)] the address
# @param rp [Records::Path] the database item
# 
def rule_path(lev, addr, rp)

   na = addr.last

   # what are the link origin node addresses, are we in one?
   node_lst = rp.link.map{|lk| lk.addr_orig[lev-1] }
   lix = node_lst.index( na )

   # no rule to add
   return nil if( !lix )

   # the link & labels
   lnk = rp.link[lix]
   lab = Records.label_path(lev, lnk.label)

   # at origin of link - forward
   if( addr == lnk.addr_orig )

      if( lix == rp.link.size-1 )
         lab_out = Records::LABEL_EOP
      else
         lab_out = Records.label_path(lev, rp.link[lix+1].label)
      end

      return [lab, :swap, [lab_out, lnk.port]]
     
   # otherwise - push the origin of link
   else
      lstk = []
      (lev-1).times do |ix|
         lstk.append( Records.label_node(lev-ix-1, 7, lnk.addr_orig[ix]) )
      end
      return [lab, :push, lstk]
   end

end # def rule_path()


#################################################
# Get the rule for a Fill
# 
# @param lev [Integer] the level
# @param addr [Array(Integer)] the address
# @param rf [Records::Fill] the database item fill
# @param rp [Records::Path] the database item path referenced
# 
def rule_fill(lev, addr, rf, rp)
   # not at the source address
   return nil if( rf.source != addr )

   # what are the path node addresses, which are we in?
   node_lst = rp.link.map{|lk| lk.addr_orig[lev-1] }
   na = addr.last
   lix = node_lst.index( na )
   if( !lix )
      log(:error, "Node not in path: %s %s %d %s" %
            [rf.id, rp.id, na, node_lst.inspect] )
      raise "Something really wrong with the routing happened"
   end

   dst = Records.label_node(lev, rf.priority, rf.destination)
   plab = Records.label_path(lev, rp.link[lix].label)
   return [dst, :set, plab]

end # def rule_fill()


#################################################
# Remove an item
# 
# @param info [Hash] info about the item
# 
def do_remove(info)

   # single rule
   if( info[:installed][:rule] )
      @nis.extif.rule_clear( info[:installed][:rule][0] )
      @nis.activity(:rule_clear, 1)
   end

   # multiple rules
   if( info[:installed][:rule_list] )
      info[:installed][:rule_list].each do |rule|
         @nis.extif.rule_clear( rule[0] )
      end
      @nis.activity(:rule_clear, info[:installed][:rule_list].size)
   end

   # mark as removed
   info.delete(:installed)

end # def remove()


#################################################
# Install an item
# 
# @param info [Hash] info about the item
# 
def do_install(info)
  
   # single rule
   if( info[:current][:rule] )
      @nis.extif.rule_set( *info[:current][:rule] )
      @nis.activity(:rule_set, 1)
   end

   # multiple rules
   if( info[:current][:rule_list] )
      info[:current][:rule_list].each do |rule|
         @nis.extif.rule_set( *rule )
      end
      @nis.activity(:rule_set, info[:current][:rule_list].size)
   end

   # mark as installed
   info[:installed] = info[:current]
   info.delete(:current)

end # def install()
  

#################################################
# Update the ingress fill
# 
# @param info [Hash] info about the ingress request
# 
def do_ingress(info)

   # install
   if( info[:current] && info[:current][:fill] )
      @nis.extif.demand_fill(info[:num], info[:current][:fill])
      info[:installed] = info[:current]

   # remove 
   else
      @nis.extif.demand_fill(info[:num], 0)
      info.delete(:installed)
   end

   info.delete(:current)

end # def do_ingress()

end # class TEZC::Info::Routes

end # module TEZC::Info
end # module TEZC
