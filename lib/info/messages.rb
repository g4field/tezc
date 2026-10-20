#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

module TEZC
module Info

##########################################################################
# Messages
#
# Messages that are exchanged with the Network Information Service
#
module Messages


##########################################################################
# PHY status message
#
class Phy

#################################################
# The port
# @return [Integer]
attr_accessor :port

#################################################
# State of the link
# @return [true,false]
attr_accessor :link

#################################################
# Speed of the link
# @return [Integer]
attr_accessor :speed

end # class TEZC::Info::Messages::Phy
##########################################################################


##########################################################################
# A port monitor message
#
class Port

#################################################
# the port associated with the message
# @return [Integer]
attr_accessor :port

#################################################
# The self and neighbor router IDs
# @return [String]
attr_accessor :s_router, :n_router

#################################################
# the self and neighbor port numbers
# @return [Integer]
attr_accessor :s_port, :n_port

#################################################
# the self and neighbor cycle numbers
# @return [Integer]
attr_accessor :s_cycle, :n_cycle

#################################################
# The self and neighbor change number
# @return [Integer]
attr_accessor :s_change, :n_change

#################################################
# If this message needs to be acknowledged promptly
# @return [true,false]
attr_accessor :required

#################################################
# the minimum distance of the link
# @return [Integer]
attr_accessor :s_min_dist

#################################################
# the hierarchical address of the router
# @return [Array(Integer)]
attr_accessor :s_addr

#################################################
# the node ID
# @return [String]
attr_accessor :s_node

#################################################
# why the message was sent
#
# This is one of the following:
# * :expired
# * :change
# * :ack
# * :keepalive
# * :retry_active
# * :retry_keepalive
# 
# @return [Symbol]
attr_accessor :reason

end # class TEZC::Info::Messages::Port
##########################################################################


##########################################################################
# The Database message
class Database

#################################################
# the port associated with the message
# @return [Integer]
attr_accessor :port

#################################################
# The area state information
# @return [Array(Hash)]
attr_accessor :areas

#################################################
# the sending router ID
# @return [String] the sending router ID
attr_accessor :sender

#################################################
# the adjacent router ID
# @return [String] 
attr_accessor :adjacent

#################################################
# The change sent in this message
# @return [Integer]
attr_accessor :change

#################################################
# The changed acked in this message
# @return [Integer]
attr_accessor :ack

#################################################
# If an ack is rquired
# @return [true,false]
attr_accessor :required

#################################################
# @return [Array(State)] the states this packet contains
attr_accessor :states

#################################################
# @return [String, nil] the requested content item ID
attr_accessor :request

#################################################
# @return [Item,nil] the content for messages that have it
attr_accessor :content

end # class TECZ::Info::Messages::Database

end # module TEZC::Info::Messages

end # module TEZC::Info
end # module TEZC