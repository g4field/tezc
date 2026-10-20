#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'
require_relative 'records'

module TEZC
module Info

##########################################################################
# Manage egress info
#
class Egress < Mod


#################################################
# New egress module
# 
# @param nis [Service] the NIS
# 
def initialize(nis)

   # save self info
   super(nis)

   # our egress info
   @id = Records.id_egress(@nis.id)
   @active = false
   @serial = 0
   @refresh = 0

   # port to customer address
   @port = {}

   # router to egress info hash
   @router = {}

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

   # register for triggers
   [  :self_address,
      :db_egress_update,
      :db_egress_remove,
   ].each{|trig| @nis.trigger_register(trig, 0, self)}

   # defaults
   @cfg_refresh = 1*60*1000      # time between refresh, default to 5 min

end # def initialize()


#################################################
# Time between refreshes
# 
# Defaults to 5 minutes
# @return [Integer] time in ms
attr_accessor :cfg_refresh


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   # if there are no active ports, we do not do anything
   return if( !@active )

   case trig

   # process an address update
   when :self_address

      # egress info changes
      do_changed()

      # customer egress
      @router.each_pair do |rt, eid|

         # check distance
         dist = @nis.address.distance(eid[:address])

         # no change
         next if( dist == eid[:distance] )

         # remove old rules
         if( eid[:distance] >= 0 )
            eid[:customer].each do |ca|
               @nis.extif.customer_clear(ca)
            end
            @nis.activity(:customer_clear, eid[:customer].size)
         end

         # set new rules
         if( dist >= 0 )
            addr = eid[:address].first(dist+1)
            eid[:customer].each do |ca|
               @nis.extif.customer_set(ca, addr)
            end
            @nis.activity(:customer_set, eid[:customer].size)
         end

         # save new distance
         eid[:distance] = dist

      end

   # egress is added or updated
   when :db_egress_update

      # ignore our own egress info
      return if( data.router == @nis.id )

      log(:verbose, "Egress rule: %s" %
         [data.id])

      # clear old rules, if any
      oldeid = @router[data.router]
      if( oldeid && oldeid[:distance] >= 0 )
         oldeid[:customer].each do |ca|
            @nis.extif.customer_clear(ca)
         end
         @nis.activity(:customer_clear, oldeid[:customer].size)
      end

      # save data
      dist = @nis.address.distance(data.address)
      eid = {
         router: data.router,
         address: data.address.dup,
         distance: dist,
         customer: data.customer.map{|ca| ca.dup}
      }
      @router[data.router] = eid

      # set new rules
      if( dist >= 0 )
         addr = eid[:address].first(dist+1)
         eid[:customer].each do |ca|
            @nis.extif.customer_set(ca, addr)
         end
         @nis.activity(:customer_set, eid[:customer].size)
      end

   # egress goes away
   when :db_egress_remove

      # ignore our own egress info
      return if( data.router == @nis.id )

      # clear old rules, if any
      oldeid = @router[data.router]
      if( oldeid && oldeid[:distance] >= 0)
         oldeid[:customer].each do |ca|
            @nis.extif.customer_clear(ca)
         end
         @nis.activity(:customer_clear, oldeid[:customer].size)
      end

      # delete data
      @router.delete(data.router)

   else
      raise "Unknown trigger received"
   end

end # def trigger()


#################################################
# (see Mod#timer)
def timer()
   @refresh = @refresh + 1
   do_send()
   @timer.expires = @nis.now + @cfg_refresh
   @nis.timer_set(@timer)
end # def timer()


#################################################
# Configure a port to egress a customer address
#
# @param port [Integer] the port to egress
# @param customer [Array(Integer)] the customer addr to exit
#
def egress_port(port, customer)
   @port[port] = customer.dup
   @active = true
   do_changed()
end # def egress_port()


################################################################
# Private
private


#################################################
# Egress info has changed
def do_changed()

   # if there are no active ports, we do not do anything
   return if( !@active )

   # if the address has not stabilized, we do not do anything
   return if( !@nis.address.stable? )

   log(:verbose, "Egress changed: addr %s" %
         [@nis.address.addr.inspect])

   # start the timer
   @timer.expires = @nis.now + @cfg_refresh
   @nis.timer_set(@timer)

   # adjust the data and send
   @serial = @serial + 1
   @refresh = 1
   do_send()
end # def do_changed()


#################################################
# Send the egress info
def do_send()

   # assemble the egress info
   ei = Records::Egress.new
   ei.id = @id
   ei.level = @nis.max_levels
   ei.serial = @serial
   ei.router = @nis.id
   ei.address = @nis.address.addr
   ei.customer = @port.values.map{|ca| ca.dup }

   # save it
   @nis.db.update(ei, @refresh)

end # def do_send()
   
end # class TEZC::Info::Egress

end # module TEZC::Info
end # module TEZC