#
# Copyright 2025 by Graham A. Field
# All Rights Reserved
#


module TEZC
module Model


##########################################################################
# Packet
#
# A model packet
class Packet

alias inspect to_s


#################################################
# Get the packet count
# @return [Hash(Integer)] the current packet count for each type
def self.count()
   return @@count
end # def self.count()


#################################################
# Packet counter
#
# Used to assign unique numbers to each packet
# @return [Integer]
@@count_all = 0


#################################################
# Packet counter per type
# @return [Hash(Integer)]
@@count = {}


#################################################
# New packet
def initialize(type)
   if( @@count.key?(type) )
      @@count[type] = @@count[type] + 1
   else
      @@count[type] = 1
   end
   @@count_all = @@count_all + 1
   @id = @@count_all

   @dest = []
   @trace = false
   @corrupt = false
   @meta_queue = Model::NEVER
   @ttl = 50

end # initialize()


#################################################
# Flag for trace packets
# @return [true, false]
attr_accessor :trace

#################################################
# Packet ID
# @return [Integer]
attr_reader :id

#################################################
# Simulation time when the packet was queued
# @return [Integer]
attr_accessor :meta_queue

#################################################
# time to live
# @return [Integer]
attr_accessor :ttl

#################################################
# The interface associated to the packet
# @return [Integer]
attr_accessor :meta_iface

#################################################
# if the packet is corrupt
# @return [true, false]
attr_accessor :corrupt


#################################################
# packet size
# @return [Integer]
attr_reader :size


#################################################
# set packet content
def content_set(data, size)
   @content = data
   @size = size
end # def content()


#################################################
# packet content
# @return [Object]
attr_reader :content


#################################################
# assign a client address
def client(addr)
   if( @dest.size > 1 )
      raise("Tried to set client address on labeled packet")
   end
   @dest.append(addr)
end # def client()


#################################################
# push a label
def push(label)
   if( @dest.size < 1 )
      raise("Tried to push a label without a client address")
   end
   @dest.append(label)
   @size = @size + 4
end # def push()


#################################################
# swap a label
def swap(label)
   if( @dest.size < 2 )
      raise("Tried to swap a non-existent label")
   end
   @dest[@dest.size-1] = label
end # def swap()


#################################################
# pop a label
def pop
   if( @dest.size < 2 )
      raise("Tried to pop a non-existent label")
   end
   @dest.pop
   @size = @size - 4
end # def pop()


#################################################
# Get the destination address/label
def dest
   return @dest.last
end # def dest


#################################################
# Get the dest as a string
def dest_str
   dst = @dest.last

   if( dst.is_a?(Integer) )
      return dst.to_s(16)
   else
      return dst.inspect
   end

end # def dest_str()


#################################################
# depth of the header stack
def depth
   @dest.size
end # def depth


end # class TECZ::Model::Packet

end # module TEZC::Model
end # module TEZC
