#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

module TEZC
module Info

##########################################################################
# A module
#
# Modules do things for the network information service.
#
class Mod

alias inspect to_s

#################################################
# new module
#
# @param nis [Service] the NIS
#
def initialize(nis)
   @nis = nis
end # def initialize()


#################################################
# Receive a trigger
#
# @param (see Service#trigger_send)
#
def trigger(trig, level, data)
   raise NotImplementedError, "Must be specified in child class"
end # def trigger()


#################################################
# Receive a timer
#
def timer()
   raise NotImplementedError, "Must be specified in child class"
end # def timer()


#################################################
# Write a log message
#
# @param lev [Symbol] the debug level
# @param msg [String] the message to write
#
def log(lev, msg)
   @nis.extif.print_log(lev, msg)
end # def log()

end # class TEZC::Info::Mod

end # module TEZC::Info
end # module TEZC