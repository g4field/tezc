#
# Copyright 2026 Graham A. Field
# All Rights Reserved
#

module TEZC
module Info

##########################################################################
# Handle customer lookups for all types of customers
# 
class Customer

#################################################
# new
def initialize()
   @type = {}
   @@typeclass.each_pair{|tp, cl| @type[tp] = cl.new }
end # def initialize()


#################################################
# The type classes
@@typeclass = {}


#################################################
# handle a type
def self.handle(type, type_class)
   @@typeclass[type] = type_class
end # def handle()
  
  
#################################################
# set
def set(cust, val)
   @type[cust[:type]].set(cust, val)
end # def set()


#################################################
# delete
def del(cust)
   @type[cust[:type]].del(cust)
end # def del()


#################################################
# lookup
def lookup(cust)
   @type[cust[:type]].lookup(cust)
end # def lookup()

end # class TEZC::Info::Customer

  
##########################################################################
# Customer Lookup 
#
class CustomerBase

#################################################
# new
def initialize()
   @store = {}
end # def initialize()


#################################################
# Set a customer address
# 
# @param addr [Integer] the address
# @param bits [Integer] the number of bits
# @param orig [Object] the original customer address
# @param val [Object] the thing we keep
# 
def set(addr, bits, orig, val)
   ix = (bits << 56) + addr
   @store[ix] = {
      val: val,
      orig: orig,
      addr: addr,
      bits: bits
   }
end # def set()


#################################################
# Delete
#
# @param addr [Integer] the address
# @param bits [Integer] the number of bits
def del(addr, bits)
   ix = (bits << 56) + addr
   @store.delete(ix)
end # def del


#################################################
# Lookup
# 
# @param addr [Integer] the address to lookup
# @param bits [Integer] bits of the address
# @return [Object] value or nil
# 
def lookup(addr, bits)

   @store.each_pair do |ix, ca|
      mask = (1 << (bits - ca[:bits])) - 1
      return ca[:val] if( (addr | mask) == (ca[:addr] | mask) )
   end
   return nil
  
end # def lookup()
  
end # class TEZC::Info::CustomerBase


##########################################################################
# Customer Lookup for Model 
#
# We have a fixed address depth of 4, with each part max 255.
# The customer addresses are:
# type: :model
# addr: [Array(Integer)]
# 
class CustomerModel < CustomerBase

#################################################
# Set a customer address
# 
def set(cust, val)

   addr = 0
   cust[:addr].each{|ad| addr = (addr << 8) + ad }
   (4-cust[:addr].size).times{|ix| addr = addr << 8}

   bits = cust[:addr].size * 8

   return super(addr, bits, cust, val)
end # def set()


#################################################
# Delete
def del(cust)
   addr = 0
   cust[:addr].each{|ad| addr = (addr << 8) + ad }
   (4-cust[:addr].size).times{|ix| addr = addr << 8}

   bits = cust[:addr].size * 8

   return super(addr, bits)
end # def del


#################################################
# Lookup
def lookup(cust)

   addr = 0
   cust[:addr].each{|ad| addr = (addr << 8) + ad }
   (4-cust[:addr].size).times{|ix| addr = addr << 8}

   return super(addr, 32) 
end # def lookup()
  

end # class TEZC::Info::CustomerModel


##########################################################################
# Customer Lookup for IPv4 
#
# The customer addresses are:
# type: :ipv4
# addr: string in CIDR format
# 
class CustomerIPv4 < CustomerBase

#################################################
# translate address
# 
def get_addr_bits(cust)
   ma = /^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)\/([0-9]+)/.match(cust[:addr])
   if( !ma )
      raise "Invalid address format"
   end

   addr = (ma[1].to_i << 24) + (ma[2].to_i << 16) + (ma[3].to_i << 8) +
      ma[4].to_i
   bits = ma[5].to_i

   return addr, bits
end

#################################################
# Set a customer address
# 
def set(cust, val)
   addr, bits = get_addr_bits(cust)
   return super(addr, bits, cust, val)
end # def set()


#################################################
# Delete
def del(cust)
   addr, bits = get_addr_bits(cust)
   return super(addr, bits)
end # def del()


#################################################
# Lookup
def lookup(cust)
   addr, bits = get_addr_bits(cust)
   return super(addr, 32)
end # def lookup()

end # class TEZC::Info::CustomerIPv4


end # module TEZC::Info
end # module TEZC