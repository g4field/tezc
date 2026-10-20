#
# Copyright 2025 by Graham A. Field
# All Rights Reserved
#


module TEZC
module Model

##########################################################################
# Item
#
# A simulation item
#
class Item

alias inspect to_s

###########################################################
# For use by {Model::Runtime}
attr_accessor :sim_run_prev, :sim_run_next, :sim_run_time


###########################################################
# Register with the simulation runtime
#
# @param sim [Runtime] the simulation runtime
# @param parent [Item, nil] the parent item, if there is one 
# @param name [String] the name of the item
#
def sim_register(sim, parent, name)

   # used by the runtime to run items
   @sim_run_prev = nil
   @sim_run_next = nil
   @sim_run_time = Model::NEVER

   # used by the runtime to debug
   @sim_loglevel = :info

   # register with the runtime
   @sim = sim
   @sim_parent = parent
   @sim_name = name
   @sim.register(self)

end # def sim_register()



###########################################################
# Calculate the sim time from seconds
#
# @param start [Integer] the start offset
# @param delay [Float] the delay in seconds
#
def sim_sec(start, delay)
   return start + (delay * @sim.resolution).ceil
end # def sim_sec()


###########################################################
# Calculate the sim time in milliseconds
#
# @param start (see #sim_sec)
# @param delay [Float] period in milliseconds
#
def sim_msec(start, delay)

   # delay ms * (st/s) * 1e-3 s/ms = delay st
   return start + (delay * @sim.resolution * 1e-3).ceil
end # def sim_msec()


###########################################################
# Calculate the sim time in microseconds
# @param start (see #sim_sec)
# @param delay [Float] period in microseconds
#
def sim_usec(start, delay)
   return start + (delay * @sim.resolution * 1e-6).ceil
end # def sim_usec()


###########################################################
# Log a message
def sim_log(level, msg)
   @sim.log_msg(self, level, msg, nil)
end # def sim_log()


###########################################################
# Log a error message
def sim_error(msg)
   @sim.log_msg(self, :error, msg, nil)
end # def sim_debug()


###########################################################
# Log a warning message
def sim_warn(msg)
   @sim.log_msg(self, :warn, msg, nil)
end # def sim_warn()


###########################################################
# Log a debug message
def sim_debug(msg)
   @sim.log_msg(self, :debug, msg, nil)
end # def sim_debug()


###########################################################
# Log an info message
def sim_info(msg)
   @sim.log_msg(self, :info, msg, nil)
end # def sim_info()


###########################################################
# Log a verbose message
def sim_verbose(msg)
   @sim.log_msg(self, :verbose, msg, nil)
end # def sim_verbose()


###########################################################
# Log a packet
#
# :trace level only logs packets with trace set
def sim_pkt(level, pkt, msg)
   @sim.log_msg(self, level, msg, pkt)
end # def sim_pkt()


###########################################################
# Log a packet drop
def sim_drop(pkt, reason)
   @sim.drop(self, pkt, reason)
end # def sim_drop()


###########################################################
# The log level for this item
attr_accessor :sim_loglevel


###########################################################
# Run the simulation for this item
#
# @param st [Integer] the simulation time
# @return [Integer] next time it needs to run, or Model::NEVER
#
def sim_run(st)
   # default is an item that never runs
   return Model::NEVER
end # def sim_run()


###########################################################
# Wake the item
#
def sim_wake()
   @sim.delay(self, 0)
end # def sim_wake()


###########################################################
# The simulation runtime
attr_accessor :sim


###########################################################
# Parent
attr_reader :sim_parent


###########################################################
# Name
attr_reader :sim_name


###########################################################
# Full name of the item
#
def sim_fullname
   return @sim_fullname if( @sim_fullname )
   
   if( @sim_parent )
      @sim_fullname = @sim_parent.sim_fullname + ':' + @sim_name
   else
      @sim_fullname = @sim_name
   end
   return @sim_fullname
end # def sim_fullname()


end # class TEZC::Model::Item

end # module TEZC::Model
end # module TEZC
