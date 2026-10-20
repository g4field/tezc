#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

require_relative 'mod'

module TEZC
module Info

##########################################################################
# Monitor stability of the network
#
# Track changes in the databases to determine when the DB
# is stable so that we can:
# * Run the area routing algorithm (:stable_route)
# * Install the results (:stable_install)
# 
# Reconfiguration of a network to minimize (or entirely avoid)
# network disruption is extremely complex.
# We chose an eventually consistent model and try to minimize
# the inconsistent time.
# 
# Area changes (new leader, partition, or election) mean
# addresses and links will be updating, egress info and demands
# will update to new addresses.
# 
# Demands, Links and routing results will feed into the routing
# of lower levels.
# 
# 
class Stable < Mod


#################################################
# New stability module
# 
def initialize(nis)

   # save
   super(nis)

   # create a timer
   @timer = Service::Timer.new
   @timer.module = self

   # is the area stable to route
   @unstable = 0

   # register for triggers
   [  :db_area,
      :db_demand_update,
      :db_demand_remove,
      :db_link_update,
      :db_link_remove,
      :db_fill_update,
      :db_fill_remove,
      :db_path_update,
      :db_path_remove,
   ].each{|trig| @nis.trigger_register(trig, 0, self)}

   # configuration
   @cfg_area = 1000             # how long to wait after an area election
   @cfg_inputs = 500            # how long to wait after inputs to algorithm change
   @cfg_route = 1000            # how long to wait for routing results to appear
   @cfg_install = 500           # how long to wait after routing results
end # def initialize()


#################################################
# (see Mod#trigger)
def trigger(trig, level, data)

   case trig

   # area changes
   when :db_area
      @unstable = [@unstable, level].max
      @timer.expires = @nis.now + @cfg_area

   # inputs to routing algorithm
   when :db_demand_update, :db_demand_remove,
      :db_link_update, :db_link_remove
      @unstable = [@unstable, level].max
      @timer.expires = @nis.now + @cfg_inputs

   # results of routing algorithm
   when :db_fill_update, :db_fill_remove,
      :db_path_update, :db_path_remove
      if( level <= 1 )
         @timer.expires = @nis.now + @cfg_install
      else
         @unstable = [@unstable, level-1].max
         @timer.expires = @nis.now + @cfg_inputs
      end
   
   else
      raise "Unknown trigger received"
   end

   # start the timer running
   timer_reset()

end # def trigger()


#################################################
# (see Mod#timer)
def timer()

   now = @nis.now

   # wait for the area to be stable for routing
   if( @unstable != 0 )

      log(:verbose, "Stable %d route" % @unstable)
      @nis.trigger(:stable_route, @unstable, nil)

      @unstable = @unstable-1
      @timer.expires = @nis.now + @cfg_route

   # wait to install
   else
      log(:verbose, "Stable install")
      @nis.trigger(:stable_install, 0, nil)

      @timer.expires = nil
   end

   timer_reset()
end # def timer()


#################################################
# timer reset
def timer_reset()

   if( @timer.expires )
      @nis.timer_set(@timer)
   else
      @nis.timer_del(@timer)
   end

end # def timer_reset()

end # class TEZC::Info::Stable
  
end # module TEZC::Info
end # module TEZC