#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require 'json'

module TEZC
module Test

##########################################################################
# Generate topologies for SimLinux
#
# We build a model, then create it:
# * router (hash name to desc):
#   * name
#   * port
#     * index
#     * customer addr
#     * core distance
# * link (hash name to desc):
#   * name
#   * speed
#   * interface a: router, port
#   * interface b: router, port
#
class SimLinuxGen

#################################################
# New generator
def initialize()
   @routers = {}
   @hosts = {}
   @links = []

end # def initialize()


#################################################
# Generate an specified topology
# 
# @param base_name [String] the base name to use
# @param spec [Hash] the specification
# @return [Integer] the highest hierarchical level
# 
def gen_specified(base_name, spec)

   # base area - we have routers
   if( spec[:routers] )

      # routers are level 0
      level = 0
     
      # generate the routers
      spec[:routers].times do |rx|
         rname = '%sr%d' % [base_name, rx]
         desc = {name: rname, ports: [], demands: [] }
         @routers[rname] = desc
      end

   # higher level area, we have areas
   elsif( spec[:areas] )

      # start counting areas at 0
      acnt = 0

      # levels of the sub-areas
      levels = []

      # generate each area
      spec[:areas].each do |ts|
         ts[:count].times do |tx|
            levels[acnt] = gen_specified(base_name + 'a%d' % acnt, ts[:spec])
            acnt = acnt + 1
         end
      end

      level = levels.max

   # nope
   else
      raise "badly formed area specification"
   end

   # add links
   if( spec[:links] )

      # start counting links at 0
      lcnt = 0

      # generate each link
      # nameA, portA, nameB, portB
      spec[:links].each do |ls|

         rtA = @routers[ base_name + ls[0] ]
         rtB = @routers[ base_name + ls[1] ]

         if( !rtA )
            raise "router not found %s" % base_name + ls[0]
         end
         if( !rtB )
            raise "router not found %s" % base_name + ls[1]
         end

         rtA[:ports].append( ['core', level, ls[2]] )
         rtB[:ports].append( ['core', level, ls[2]] )

         desc = {
            rtA: rtA[:name],
            rtB: rtB[:name],
            portA: rtA[:ports].size - 1,
            portB: rtB[:ports].size - 1,
            speed: ls[2]
         }

         @links.append( desc )
      end

   end

   # we are one level up
   return level + 1

end # def gen_specified()


#################################################
# Add a host
#
# @param name [String] the name of the host
# @param rtr [String] the router to connect to
# @param ip [String] the IP address of the host
# @param gw [String] the IP address of the router
# @param cidr [Integer] the CIDR range
# @param spd [Integer] the speed for the link
# @return [Integer] the port number on the router
#
def host_add(name, rtr, ip, gw, cidr, spd)

   rt = @routers[ rtr ]
   if( !rt )
      raise "router not found %s" % rtr
   end

   # add the host
   desc = {
      name: name,
      ip: '%s/%d' % [ip, cidr],
      gw: gw,
   }
   @hosts[name] = desc

   # the router port
   desc = [
      'customer',
      '%s/%d' % [gw, cidr],
      spd
   ]
   rt[:ports].append( desc )

   # the link
   desc = {
      rtA: rt[:name],
      rtB: name,
      portA: rt[:ports].size - 1,
      portB: 0,
      speed: spd,
   }
   @links.append( desc )

   return desc[:portA]

end # def host_add()


#################################################
# Add a demand
# 
# @param rtr [String] the router
# @param port [Integer] the port on the router
# @param addr [String] the destination address
# @param pri [Integer] the priority
# @param spd [Integer] the speed requested
# 
def demand_add(rtr, port, addr, pri, spd)
   rt = @routers[ rtr ]
   if( !rt )
      raise "router not found %s" % rtr
   end

   # add the demand
   rt[:demands].append([port, addr, pri, spd])
end # def demand_add()


#################################################
# The Mininet python template, preamble
PYTHON_MININET_PRE = <<-EOF

from mininet.topo import Topo
from mininet.net import Mininet
from mininet.node import Node
from mininet.link import TCLink
from mininet.log import setLogLevel, info
from mininet.cli import CLI

class TezcTopo( Topo ):

   # pylint: disable=arguments-differ
   def build( self, **_opts ):

EOF

#################################################
# The Mininet python template, post
PYTHON_MININET_POST = <<-EOF


def run():
   topo = TezcTopo()
   net = Mininet(controller=None, link=TCLink, topo=topo )
   net.start()

   # run router script on each router
   info('starting routers...')
   for rtr in net.hosts:
      rtr.cmd('../sim_linux/router.rb' + ' ' + rtr.name + ' &')

   CLI( net )
   net.stop()


if __name__ == '__main__':
   setLogLevel( 'info' )
   run()
EOF

#################################################
# Build the topology
# 
def build(dir)

   # create the directory
   Dir.mkdir(dir)

   # python data
   py_build = []

   # build routers
   @routers.each_pair do |name, desc|

      # build the ports
      ports = []
      desc[:ports].each_index do |ix|
         pd = desc[:ports][ix]
         devname = name + '-eth%d' % ix
         ports.append( [devname] + pd )
      end

      # generate JSON
      config = {
         'name' => name,
         'ports' => ports,
         'demands' => desc[:demands],
      }
      json = JSON.pretty_generate(config)

      # write the SimLinux configuration
      rdir = File.join(dir, name)
      rcfg = File.join(dir, name, 'config.json')
      Dir.mkdir(rdir)
      File.open(rcfg, 'w'){|cfg| cfg.write(json) }

      # python build
      build = "      %s = self.addNode('%s', ip=None)" % [name, name]
      py_build.append( build )
   end

   # build hosts
   @hosts.each_pair do |name, desc|
      build = "      %s = self.addHost('%s', ip='%s', defaultRoute='via %s' )" % [
            desc[:name], desc[:name],
            desc[:ip], desc[:gw]
         ]
      py_build.append( build )
   end

   # build links
   @links.each do |desc|

      build = "      self.addLink(%s, %s, intfName1='%s-eth%d', intfName2='%s-eth%d', bw=%f)" % [
            desc[:rtA],
            desc[:rtB],
            desc[:rtA], desc[:portA],
            desc[:rtB], desc[:portB],
            desc[:speed].to_f/1000.0
         ]
      py_build.append( build )

   end

   # write the python mininet topology
   mcfg = File.join(dir, 'topo.py')
   File.open(mcfg, 'w') do |py|
      py.write(PYTHON_MININET_PRE)
      py.write( py_build.join("\n") )
      py.write(PYTHON_MININET_POST)
   end

   # create the log fifo
   fifoname = File.join(dir, 'fifolog')
   File.mkfifo(fifoname)

end # def build()


end # class TEZC::Test::SimLinuxGen

end # module TEZC::Test
end # module TEZC
