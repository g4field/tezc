#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'item'

module TEZC
module Model

##########################################################################
# Routing Algorithm Service
# 
class RAS < Item


#################################################
# Set the algorithm
#
# @param algo [Object] that implements #route and returns results
#
def self.set_algo(algo)
   @@algo = algo
end # def self.set_algo()


#################################################
# New algo
def initialize(parent, name)

   # register with the simulation
   sim_register(parent.sim, parent, name)

   @completion = Model::NEVER

   @cfg_algorithm = sim_sec(0, 0.5)         # time for the algorithm to run

end # def initialize()


#################################################
# time for the algorithm to run
# 
# Default is 1s
# @return [Integer]
attr_accessor :cfg_algorithm


#################################################
# Access to the algorithm
attr_reader :algo


#################################################
# Run the algorithm
# 
def route_start(data, callback)

   # save the callback
   @callback = callback

   # run the algorithm
   @results = @@algo.route(data)

   # set our completion time and wake up
   @completion = @sim.time + @cfg_algorithm
   sim_wake()

end # def route_start()


#################################################
# (see Item#sim_run)
def sim_run(st)

   # call the callback after we are complete
   if( st >= @completion )
      @callback.route_results(@results)
      @completion = Model::NEVER
   end

   return @completion
   
end # def sim_run()


end # class TEZC::Model::RAS


end # module TEZC::Model
end # module TEZC