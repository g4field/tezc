#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative '../algo/demand'
require_relative 'mod'
require_relative 'records'

module TEZC
module Info
  
##########################################################################
# Manage the routing algorithm
#
# Manage the Fill and Path IDs and serials.
#    
# Run the router and sync the database with the results.
#
class Algorithm < Mod

#################################################
# new algorithms module
# 
# @param nis [Service] the NIS
# 
def initialize(nis)

   # save self info
   super(nis)
  
   # state
   @level = 0
   @state = :none
   @results = nil
  
   # manage the Fill and Path ID and serials
   @fill_info = Array.new(@nis.max_levels){ Hash.new }
   @path_info = Array.new(@nis.max_levels){ Hash.new }

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

   # register for triggers
   [  :stable_route
   ].each{|trig| @nis.trigger_register(trig, 0, self)}

end # def initialize()


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig

   # stable enough to route
   when :stable_route

      # only do something if we are the leader
      return if( @nis.db.area[level-1][:leader] != @nis.id )

      # we are routing something
      if( @state != :none )
         raise "Algorithm already doing something, can not start"
      end

      # flag it to start
      @state = :start
      @level = level
   
   else
      raise "Unknown trigger received"
   end

   # do processing under the timer
   @timer.expires = @nis.now - 1
   @nis.timer_set(@timer)

end # def trigger()


#################################################
# (see Mod#timer)
def timer()

   case @state
     
   # starting
   when :start

      if( route() )
         @state = :running
      else
         @state = :none
      end

   # resulting
   when :results

      results()
      @state = :none      

   # something else
   else
      raise "Unexpected timer"
   end
   
   # only run once
   @nis.timer_del(@timer)

end # def timer()
  


################################################
# extif - get routing results
# 
# @param res [Hash] the results hash, including
#   :level, :demands, :paths
# 
def route_results(res)

   # not running
   if( @state != :running )
      raise "Got results, but routing not running"
   end

   # wrong level
   if( res[:level] != @level )
      raise "Got results, wrong level"
   end

   # save the results
   @results = res
   @state = :results

   # do processing under the timer
   @timer.expires = @nis.now - 1
   @nis.timer_set(@timer)

end # def route_results()


################################################################
private


#################################################
# Route
# 
# @return [true,false] if we had anything to route
# 
def route()

   # we are the area leader
   area = @nis.id

   ##########################
   ##########################
   # calculate demands

   # get the demand from the database
   #  at or above this level
   demands = []
   @nis.address.used.times do |ix|

      # demand
      demands[ix] = []
      @nis.db.each(ix+1, :demand) do |td|

         # create the listable demand
         dl = TEZC::Algorithm::Demand.new
         dl.id = td.id
         dl.source = td.source.dup
         dl.priority = td.priority
         dl.destination = td.destination.dup
         dl.speed = td.speed
         dl.original = true

         # put it on the list
         demands[ix].append(dl)
      end

   end

   # calculate demands derived from route results
   # process all used levels above our level
   fills = {}
   paths = {}
   ix = @nis.address.used - 1
   while( ix >= @level-1 )

      # get Fills from database
      fills = {}
      @nis.db.each(ix+1, :fill) do |rf|
         if( fills[rf.demand] )
            fills[rf.demand] = 0
            log(:warn, "Algo %d duplicate fill %d at level %d" %
                  [@level, rf.demand, ix+1])
         else
            fills[rf.demand] = rf
         end
      end
      fills.delete_if{|fn, rf| rf == 0 }

      # get Paths from database
      paths = {}
      @nis.db.each(ix+1, :path) do |rp|
         if( paths[rp.path] )
            paths[rp.path] = 0
            log(:warn, "Algo %d duplicate path %d at level %d" %
                  [@level, rp.path, ix+1])
         else
            paths[rp.path] = rp
         end
      end
      paths.delete_if{|pn, rp| rp == 0 }

      # break on our level
      break if( ix == @level-1 )

      # what is our node address in this level
      na = @nis.address.addr[ix]

      # run thru all routed fills
      fills.each_pair do |num, rf|

         # get corresponding path
         rp = paths[rf.path]

         # if we have both the fill and path, process
         if( rp )
            demand_proc(demands, ix, na, rf, rp)
         end
      end

      ix = ix - 1
   end
   
   # at our level
   ix = @level-1

   # get Link from database
   links = []
   @nis.db.each(@level, :link){|ld| links.append( ld ) }
 
   # no demands or no links
   if( !demands[ix] || demands[ix].empty? || links.empty? )
      log(:info, "Algo %d no demands to route" % @level)

      # remove existing results
      fills.each_pair{|num, rf| @nis.db.remove(rf.id, rf.serial + 1) }
      paths.each_pair{|num, rp| @nis.db.remove(rp.id, rp.serial + 1) }

      return false
   end

   # log
   log(:info, "Algo %d starting route" % @level)

   # call the router
   @nis.extif.route_start({
      level: @level,
      links: links,
      demands: demands[ix],
      fills: fills,
      paths: paths,
   })

   return true
end # def route()


################################################
# get routing results
# 
# Inserts the routing results into the database.
# Removes old routing results from the database.
# 
def results()

   # easy access
   area = @nis.id
   fills = @results[:fills]
   paths = @results[:paths]

   # log
   log(:info, "Algo %d results processing" % @level)

   # delete all existing non-replaced
   del = [] 
   @nis.db.each(@level,:fill) do |rf|
      next if( fills[rf.demand] && rf.area == area )
      del.append(rf)
   end
   @nis.db.each(@level, :path) do |rp|
      next if( paths[rp.path] && rp.area == area )
      del.append(rp)
   end
   del.each{|it| @nis.db.remove(it.id, it.serial + 1) }
   
   # insert fills
   fills.each_pair do |num, it|

      # get the info
      info = results_fill(@level, num)
      
      # set the area, id and serial
      it.area = area
      it.level = @level
      it.id = info[:id]
      info[:serial] = info[:serial] + 2
      it.serial = info[:serial]

      # insert the item into the database
      @nis.db.update(it, 1)
   end

   # insert paths
   paths.each_pair do |num, it|

      # get the info
      info = results_path(@level, num)
      
      # set the area, id and serial
      it.area = area
      it.level = @level
      it.id = info[:id]
      info[:serial] = info[:serial] + 2
      it.serial = info[:serial]

      # insert the item into the database and list
      @nis.db.update(it, 1)
   end

end # def results()


#################################################
# Get the info structure for Fills
# 
# @param lv [Integer] the level
# @param num [Integer] the demand number
# @return [Hash] the info structure
# 
def results_fill(lv, num)

   info = @fill_info[lv-1][num]

   if( !info )
      id = Info::Records.id_fill(@nis.id, lv, num)

      info = {
         id: id,
         serial: 1
      }
      @fill_info[lv-1][num] = info
   end

   return info
end # def results_fill()


#################################################
# Get the info structure for Path
# 
# @param lv [Integer] the level
# @param num [Integer] the path number
# @return [Hash] the info structure
# 
def results_path(lv, num)

   info = @path_info[lv-1][num]

   if( !info )
      id = Info::Records.id_path(@nis.id, lv, num)

      info = {
         id: id,
         serial: 1
      }
      @path_info[lv-1][num] = info
   end

   return info
end # def results_path()


#################################################
# Process a demand
# 
# @param dm [Array(Array(Algorithm::Demand))] the array of demands by level
# @param ix [Integer] the level index (i.e. level - 1)
# @param na [Integer] our node address at the level
# @param fd [Records::Fill] the filled demand
# @param fp [Records::Path] the filled path
# 
def demand_proc(dm, ix, na, fd, fp)

   path_len = fp.link.size

   lx = fp.link.index{|lk| lk.addr_orig[ix] == na }

   # in source node
   if( fd.source.last == na )
      link_origin = fp.link[0].addr_orig.first(ix)

      dm[ix].each do |dlo|
         
         # matches demand
         if( demand_match(fd, dlo) )
            dlg = TEZC::Algorithm::Demand.new
            dlg.id = dlo.id
            dlg.priority = 7
            dlg.original = false
            dlg.source = dlo.source.first(ix)
            dlg.destination = link_origin.dup
            dlg.speed = fd.speed * dlo.speed / fd.speed_request
            demand_insert(dm, dlg)
         end
      end
         
   # in destination node
   elsif( fp.link.last.addr_term[ix] == na )
      link_term = fp.link[path_len-1].addr_term.first(ix)

      dm[ix].each do |dlo|

         # matches demand
         if( demand_match(fd, dlo) )
            dlg = TEZC::Algorithm::Demand.new
            dlg.id = dlo.id
            dlg.priority = 7
            dlg.original = false
            dlg.source = link_term.dup
            dlg.destination = dlo.destination.first(ix)
            dlg.speed = fd.speed * dlo.speed / fd.speed_request
            demand_insert(dm, dlg)
         end
      end

   # in intermediate node
   elsif( lx )   
      dlg = TEZC::Algorithm::Demand.new
      dlg.id = fd.id
      dlg.priority = 7
      dlg.original = false
      dlg.source = fp.link[lx-1].addr_term.first(ix)
      dlg.destination = fp.link[lx].addr_orig.first(ix)
      dlg.speed = fd.speed
      demand_insert(dm, dlg)
   end   
  
end # def demand_proc()


#################################################
# Do we match?
# 
# @param fd [Fill] the routed demand
# @param dl [Algorithm::Demand] the listed demand
# @return [true,false]
# 
def demand_match(fd, dl)

   return (
      fd.source == dl.source &&
      fd.destination == dl.destination.last
   ) 
     
end # def demand_match()


#################################################
# insert a demand
# 
# @param dm [Array(Array(Algorithm::Demand))] the array of demands by level
# @param dl [Algorithm::Demand] the demand
# 
def demand_insert(dm, dl)

   # eliminate matching address components
   while( dl.source.size > 0 && dl.source.last == dl.destination.last )
      dl.source.pop
      dl.destination.pop
   end

   # have a demand to insert
   if( dl.source.size > 0 )
      
      dm[dl.source.size - 1].append( dl )
   end
  
end # def demand_insert()
  
end # class TEZC::Info::Algorithm

end # module TEZC::Info
end # module TEZC