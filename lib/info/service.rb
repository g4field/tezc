#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'records'
require_relative 'messages'
require_relative 'address'
require_relative 'egress'
require_relative 'port'
require_relative 'database'
require_relative 'area'
require_relative 'routes'
require_relative 'demands'
require_relative 'algorithm'
require_relative 'stable'

module TEZC
module Info

##########################################################################
# Network Information Service
#
# The external interface consists of two parts.
# First, we are called using call()
# Second, we request the device do something using extif
# 
class Service

alias inspect to_s


#################################################
# New Network Information Service
#
# @param extif [Object] the external interface object
# @param levels [Integer] the number of hierarchical levels in the network
# @param ports [Integer] the number of ports on the router
# @param rand [String] random information used to generate the ID
# @param now [Integer] the startup time
#
def initialize(extif, levels, ports, rand, now=1)

   @extif = extif
   @max_levels = levels
   @max_ports = ports

   # start at time at specified
   @now = now

   @trigs = {}
   @pending = []
   @timer = {}

   # add some unregistered triggers that are needed by #call
   @trigs[:msg_port] = [ [] ]
   @trigs[:msg_phy] = [ [] ]
   sm = []
   levels.times{|ix| sm[ix] = [] }
   @trigs[:msg_database] = sm

   # set the router ID
   @id = Records.id_router(rand)

   # add the address module
   @address = Address.new(self)

   # add a port status module for each port
   @port = Array.new(@max_ports){|ix| Port.new(self, ix) }
   @port_client = Array.new(@max_ports, false)

   # add the Database module
   @db = Database.new(self)

   # add the area controllers
   @areas = Array.new(@max_levels){|ix| Area.new(self, ix+1) }

   # add the stability manager
   @stable = Stable.new(self)

   # add the routes manager
   @routes = Routes.new(self)

   # add the demands manager
   @demands = Demands.new(self)

   # add the egress manager
   @egress = Egress.new(self)

   # add the algorithm manager
   @algo = Algorithm.new(self)

end # def initialize()


#################################################
# the address module
attr_reader :address

#################################################
# The algorithm manager
# 
# This is for debugging only.
# Do not use directly.
attr_reader :algo

#################################################
# The database
# 
attr_reader :db

#################################################
# The demands module
attr_reader :demands


#################################################
# External interface to call the NIS
#
# Called in response to:
# * Port Management or Database packet message arriving.
# * Routing results available
# * Expired timer.
#
# @param now [Integer] the current time in ms
# @param msg [Message, nil] the message received, or nil
# @param res [Hash] the routing results, or nil
# @return [Integer] expiration time for the timer, or 0 if none
#
def call(now, msg, res)
   @now = now

   # clear out the what did records
   @acts = {}
   activity(:general, 1)

   # if we have a message pass it to every module that asked for it
   if( msg )
      if( msg.is_a?(Messages::Port) )
         trigger(:msg_port, 0, msg)

      elsif( msg.is_a?(Messages::Phy) )
         trigger(:msg_phy, 0, msg)

      elsif( msg.is_a?(Messages::Database) )
         trigger(:msg_database, 0, msg)

      else
         raise ArgumentError, "Unknown message type"
      end

   # routing results
   elsif( res )
      # pass the results to the algorithm manager
      @algo.route_results(res)

   # expired timer
   else
      run_now = @timer.select{|tid, tm| @now >= tm.expires }
      run_now.each_pair do |tid, tm|
         tm.module.timer()
      end
   end

   # run triggered stuff
   trigger_run()

   # what timers do we have to run
   if( @timer.empty? )
      return 0, @acts.dup
   else
      nxt_timer = @timer.values.map{|tm| tm.expires }.min
      return nxt_timer, @acts.dup
   end

end # def call()


#################################################
# Record an activity
# 
# @param sym [Symbol] what we did
# @param cnt [Integer] how many times
# 
def activity(sym, cnt)
   prio = (@acts[sym]) ? @acts[sym] : 0
   @acts[sym] = prio + cnt
end # def did_activity()


#################################################
# Set the min distance on a port
# 
# @param port [Integer] the port to set
# @param dist [Integer] the minimum distance
# 
def cfg_distance(port, dist)
   @port[port].set_dist(dist)
end # def cfg_distance()


#################################################
# Set a port as a client port
# 
# This should only be called soon after startup
# on a port that is not connected to anything yet.
# In the future, it could be re-designed to be more
# friendly to switching between client and network
# status.
# 
# @param port [Integer] the port to set
# @param val [true, false] if the port is a client
# 
def cfg_client(port, val)
   
   # make sure we only call with val true
   if( !val )
      raise "cfg_client only switches to client at this time"
   end

   # save the port manager
   @port_client[port] = @port[port]
   @port[port] = false

end # def cfg_client()


#################################################
# (see Egress#egress_port)
def set_egress(port, customer)

   # if port is not already client, set it
   cfg_client(port, true) if( @port[port] )
      
   # pass along to traffic manager
   @egress.egress_port(port, customer)
  
end # def set_egress()


#################################################
# (see Demands#demand_set)
def demand_set(num, customer, priority, speed)
   @demands.demand_set(num, customer, priority, speed)
end # def demand_set()


#################################################
# The router ID
# @return [String]
attr_reader :id


#################################################
# Maximum hierarchical levels in the network
# @return [Integer]
attr_reader :max_levels


#################################################
# Maximum ports on the router
# @return [Integer] 
attr_reader :max_ports


#################################################
# External interface for the NIS to call.
#
# This objects provides methods:
# * send_message(message)
# * print_log(level, text_to_print)
# * set routing rules (rule_set, rule_clear, rule_clear_all)
# * access the routing algorithm (route)
#
# @return [Object] the external interface
attr_reader :extif


#################################################
# The current time in ms
# 
# This is dependent on what the external interface passes in
# and is not updated except by #call.
# 
# It also gets tweaked by Model::NIS#test_debug
#
# @return [Integer] the current time in ms
#
attr_accessor :now


#################################################
# Send a trigger
#
# @param trig [Symbol] the trigger
# @param level [Integer] the associated level, or 0 for none
# @param data [Object] data that comes with the trigger 
#
def trigger(trig, level, data)
   @pending.push( [trig, level, data] )
end # def trigger()


#################################################
# Run the triggers
def trigger_run()
   while( !@pending.empty? )
      trig, level, data = @pending.shift
      trigger_dispatch(trig, level, data)
   end
end # end trigger_run()

  
#################################################
# Dispatch the trigger to the registered ones
# 
# @param trig [Symbol] the trigger
# @param level [Integer] the associated level, or 0 for none
# @param data [Object] data that comes with the trigger 
#
def trigger_dispatch(trig, level, data)

   # drop unregisted triggers
   if( !@trigs.key?(trig) )
      @extif.print_log(:warn, "Trigger with no receivers %s level %d" %
         [trig, level])
      return
   end
   
   # no level, dispatch to all registered for any level
   if( level == 0 )
      @trigs[trig].each do |ml|
         ml.each do |mod|
            mod.trigger(trig, level, data)
         end
      end

   # has a level, dispatch to all registered for 0 or that level
   else
      ml = @trigs[trig][0]
      ml.each do |mod|
         mod.trigger(trig, level, data)
      end

      ml = @trigs[trig][level]
      ml = [] if( !ml )
      ml.each do |mod|
         mod.trigger(trig, level, data)
      end
   end
end # def trigger_dispatch()


#################################################
# Register to receive a trigger
#
# @param trig (see #trigger_send)
# @param level (see #trigger_send)
# @param mod [Module] the module to receive the trigger
#
def trigger_register(trig, level, mod)

   tl = @trigs[trig]
   if( !tl )
      tl = []
      tl[0] = []
      @trigs[trig] = tl
   end

   ml = tl[level]
   if( !ml )
      ml = []
      tl[level] = ml
   end

   ml.append(mod)

end # def trigger_register()


#################################################
# add a timer
#
# @param tm [Timer] the timer to add
#
def timer_set(tm)
   @timer[tm.id] = tm
end # def timer_set()


#################################################
# delete a timer
def timer_del(tm)
   @timer.delete(tm.id)
end # def timer_del()


##########################################################################
# a timer
class Timer

@@count = 0

def initialize()
   @@count = @@count + 1
   @id = @@count
end # def initialize()

attr_reader :id
attr_accessor :module
attr_accessor :expires

end # class TEZC::Info::Service::Timer

end # class TEZC::Info::Service

end # module TEZC::Info
end # module TEZC
