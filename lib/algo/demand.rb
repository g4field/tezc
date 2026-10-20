#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

module TEZC
module Algorithm

##########################################################################
# The demands we keep in a list
class Demand

#################################################
# The ID of the original request
# @return [String]
attr_accessor :id

#################################################
# Is the demand original?
# @return [true,false]
attr_accessor :original

#################################################
# Priority
# @return [Integer]
attr_accessor :priority

#################################################
# The source prefix
# @return [Array(Integer)]
attr_accessor :source

#################################################
# The destination prefix
# @return [Array(Integer)]
attr_accessor :destination

#################################################
# The requested speed
# @return [Array(Integer)]
attr_accessor :speed


#################################################
# encode to Hash
def encode()
   return {
      "id" => @id,
      "original" => @original,
      "priority" => @priority,
      "source" => @source,
      "destination" => @destination,
      "speed" => @speed
   }
end


#################################################
# decode from Hash
def self.decode(he)
   td = self.new

   td.id = he["id"]
   td.original = he["original"]
   td.priority = he["priority"]
   td.source = he["source"]
   td.destination = he["destination"]
   td.speed = he["speed"]

   return td  
end # def self.decode()

end # class TEZC::Algorithm::Demand 

end # module TEZC::Algorithm
end # module TEZC