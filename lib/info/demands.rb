#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'
require_relative 'records'
require_relative 'customer'

module TEZC
module Info

##########################################################################
# Handle Demand information
# 
# 
class Demands < Mod


#################################################
# New Demands module
# 
# @param nis [Service] the NIS
# 
def initialize(nis)

   # save self info
   super(nis)

   # customer address to EI
   @egress_customer = Customer.new()

   # router to EI
   @egress_router = {}

   # local number to TD
   @local = {}

   # router to active local TD
   @demand_router = {}

   # inactive demands
   @inactive = []

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

   # register for triggers
   [  :self_address,
      :db_egress_update,
      :db_egress_remove,
   ].each{|trig| @nis.trigger_register(trig, 0, self)}

   @cfg_refresh = 1*60*1000      # time between refresh, default to 5 min

end # def initialize()


#################################################
# The local demands
# 
# Should only be read.
# Hash keys are demand number.
# Each value is a Hash describing the demand,
# organized with the following keys:
# * As provided in call to {#demand_set}
#   * :num The demand number
#   * :customer The customer destination address
#   * :priority The requested priority
#   * :speed The requested speed
# * Used to update the database
#   * :id The database ID
#   * :serial The current database serial
#   * :refresh The current database refresh
#   * :time_refresh The last refresh time
# * Derived from egress info
#   * :router The egress router ID
#   * :level The level of the demand
#   * :source The source address (this router)
#   * :dest The destination address (the egress router)
#
# @return [Hash(Hash)]
attr_reader :local


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig

   # process an address update
   when :self_address

      # update demands
      @local.each_pair do |id, dm|
         next if( dm[:level] < level )
         demand_changed(dm)
      end

   # process an egress update
   when :db_egress_update
      egress_update(data)

   # process an egress remove
   when :db_egress_remove
      egress_remove(data)

   else
      raise "Unknown trigger received"
   end

   timer_update()
end # def trigger()


#################################################
# (see Mod#timer)
def timer()

   now = @nis.now

   @local.each_pair do |num, dm|
      next if( !dm[:time_refresh] || now < (dm[:time_refresh] + @cfg_refresh) )

      dm[:refresh] = dm[:refresh] + 1
      dm[:time_refresh] = now
      demand_send(dm)
   end

   timer_update()
end # def timer()


#################################################
# Create a traffic demand
#
# @param num [Integer] the demand number
# @param customer [Hash] the customer address destination
# @param priority [Integer] the priority level
# @param speed [Integer] the requested speed
# 
def demand_set(num, customer, priority, speed)

   log(:verbose, "Demand set %d %s %d %d" %
      [num, customer.inspect, priority, speed] )

   # no change
   dm = @local[num]
   return if( dm &&
         dm[:customer] == customer &&
         dm[:priority] == priority &&
         dm[:speed] == speed )

   # brand new demand
   if( !dm )
      dm = {
         num: num,
         id: Info::Records.id_demand(@nis.id, num),
         serial: 0,
         refresh: 1,
         time_refresh: nil,
         priority: nil,
         speed: 0,
         router: nil,
         level: 0,
         source: nil,
         dest: nil,
      }
      @local[num] = dm

      # put on list of inactive demands
      @inactive.append(num)
   end

   # save the customer and speed
   dm[:customer] = customer.dup
   dm[:priority] = priority
   dm[:speed] = speed

   # send the updates
   demand_changed(dm, true)

   timer_update()
end # def demand_set()


################################################################
# Private
private


#################################################
# Update the timer
# 
# We use the timer to send refreshes
def timer_update()

   # all of the active refresh times
   earliest = @local.values.map{|dm| dm[:time_refresh]}.compact.min
   
   if( earliest )
      @timer.expires = earliest + @cfg_refresh
      @nis.timer_set(@timer)
   else
      @nis.timer_del(@timer)
   end
end # def timer_update()


#################################################
# A demand has changed
# 
def demand_changed(dm, force=false)

   log(:verbose, "Demand changed %d %s %d %d" %
      [dm[:num], dm[:customer].inspect, dm[:priority], dm[:speed]] )

   #####################
   # Calculate demand info based on current status
   
   # keep old level, source, destination
   old_router = dm[:router]
   old_level = dm[:level]
   old_source = dm[:source]
   old_dest = dm[:dest]
   
   # lookup egress router based on customer address
   eid = @egress_customer.lookup(dm[:customer])

   # calculate the level
   if( eid )
      lev = @nis.address.used
      while( lev > 0 )

         aa = @nis.address.addr[lev-1]
         bb = eid[:addr][lev-1]
      
         # one side does not have an address (yet)
         if( !aa || bb == 0 )
            lev = 0

         # match, keep looking
         elsif( aa == bb )
            lev = lev - 1

         # no match, done
         else
            break
         end
      end
   end

   # have a valid Demand or not
   if( eid && lev != 0 )
      dm[:router] = eid[:router]
      dm[:level] = lev
      dm[:source] = @nis.address.addr.first(lev)
      dm[:dest] = eid[:addr].first(lev)
   else
      dm[:router] = nil
      dm[:level] = 0
      dm[:source] = nil
      dm[:dest] = nil
   end

   #####################
   # Update mappings
   
   # router to active local demand
   if( dm[:router] != old_router )

      # remove old mapping
      if( old_router )
         dl = @demand_router[old_router]
         dl.delete(dm[:num])
         if( dl.empty? )
            @demand_router.delete(old_router)
         end
      end

      # add new mapping
      if( dm[:router] )
         dl = @demand_router[dm[:router]]
         if( !dl )
            dl = []
            @demand_router[dm[:router]] = dl
         end
         dl.append(dm[:num])        
      end
   end
   
   # inactive local demand
   # remove old mapping
   if( !old_router && dm[:router] )
      @inactive.delete( dm[:num] )
   end
   # add new mapping
   if( old_router && !dm[:router])
      @inactive.append( dm[:num] )
   end   
   
   #####################
   # Update Demand in the databases
   
   # nothing changed
   return if( !force &&
         dm[:router] == old_router &&
         dm[:level] == old_level &&
         dm[:source] == old_source &&
         dm[:dest] == old_dest )

   # bump the serial
   dm[:serial] = dm[:serial] + 1
   dm[:refresh] = 1

   # update or delete
   if( dm[:router] )
      dm[:time_refresh] = @nis.now
      demand_send(dm)
   else
      dm[:time_refresh] = nil
      @nis.db.remove(dm[:id], dm[:serial])
   end

end # def demand_changed()


#################################################
# Send the demand
def demand_send(dm)

   # assemble the traffic demand
   td = Records::Demand.new
   td.id = dm[:id]
   td.level = dm[:level]
   td.router = @nis.id
   td.serial = dm[:serial]
   td.priority = dm[:priority]
   td.speed = dm[:speed]
   td.source = dm[:source]
   td.destination = dm[:dest]

   # save it in the database
   @nis.db.update(td, dm[:refresh])

end # def demand_send()


#################################################
# Process an egress info update
# 
# We store:
# * egress router -> address & prefix
# * customer prefix -> router
# 
def egress_update(ei)

   log(:verbose, "Demand egress update %s %s" %
      [ei.router, ei.customer.inspect] )

   # the new EI data
   eid = {
      router: ei.router,
      addr: ei.address.dup,
      customer: ei.customer.map{|ca| ca.dup}
   }

   # router to EI data
   oldeid = @egress_router[ei.router]
   @egress_router[ei.router] = eid

    # remove the old customer addresses
   if( oldeid )
      oldeid[:customer].each do |ca|
         @egress_customer.del(ca)
      end
   end

   # set the new customer addresses
   eid[:customer].each do |ca|
      @egress_customer.set(ca, eid)
   end

   # active local demands using this egress
   dl = @demand_router[ei.router]
   if( dl )
      dl.each do |num|
         demand_changed(@local[num])
      end
   end

   # check inactive local demands waiting for the address
   dl = @inactive.select do |num|
      dm = @local[num]
      @egress_customer.lookup(dm[:customer])
   end
   dl.each do |num|
      demand_changed(@local[num])
   end

end # def egress_update()


#################################################
# Process an egress info removal
def egress_remove(ei)

   # not our own ei
   dorule = ( ei.router != @nis.id )

   # router to EI data
   oldeid = @egress_router[ei.router]
   @egress_router.delete(ei.router)

   # customer address to EI data
   if( oldeid )
      oldeid[:customer].each do |ca|
         @egress_customer.del(ca)
      end
   end

   # active local demands using this egress
   dl = @demand_router[ei.router]
   if( dl )
      dl.each do |num|
         demand_changed(@local[num])
      end
   end

end # def egress_remove()
   
end # class TEZC::Info::Demands

end # module TEZC::Info
end # module TEZC
