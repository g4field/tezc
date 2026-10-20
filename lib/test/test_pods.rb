#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative '../model/runtime'
require_relative '../model/gen_packets'
require_relative 'topologies'
require_relative '../algo/avoid_cong'

#################################################
# Create a pod
def pod_create()

   # 12 routers
   links = []
   desc = {
      routers: [{count: 12, spec: {ports: 16} },],
      links: links
   }

   # full mesh of links
   12.times do |rix|
      (11-rix).times do |oix|
         lk = [
            'r%d' % rix,
            rix + oix,
            'r%d' % [rix + oix + 1],
            rix
         ]
         links.push(lk)
      end
   end
  
   return desc
end # def pod_create()


#################################################
# Create a network
def net_create(podcnt)

   # create the pod description
   pod_spec = pod_create()

   # create the network
   links = []
   spec = {
      areas: [
         { count: podcnt+1, spec: pod_spec },
      ],

      links: links
   }
 
   # create intra-area links for the main network
   port_b = 0
   pix_b = 0
   (podcnt-1).times do |pix_a|

      # if we were going to do this pod next
      # else we already did it.
      if( pix_b == pix_a )
         port_a = port_b
         pix_b = pix_a+1
      else
         port_a = port_b+1
      end

      # assign each external link
      while( port_a < 36 )
         lk = [
            'a%dr%d' % [pix_a, port_a/3],
            11 + (port_a % 3),
            'a%dr%d' % [pix_b, port_b/3],
            11 + (port_b % 3),
         ]
         links.push(lk)

         # next neighbor/port 
         pix_b = pix_b + 1
         if( pix_b >= podcnt )
            pix_b = pix_a + 1
            port_b = port_b + 1
         end
         port_a = port_a + 1
      end

   end

   # tack on the extra pod with a single link
   lk = [
         'a%dr1' % [podcnt-1],
         14,
         'a%dr1' % podcnt,
         11,
      ]
   links.push(lk)

   return spec

end # def net_create()


module TEZC
module Test

class TestPods < Model::Item

def initialize(sim, name, gens, podcnt)
   sim_register(sim, nil, name)
   sim_wake()

   @gens = gens
   @podcnt = podcnt
end # def initialize()

def sim_run(st)

   # wait until 20 s
   if( st < 20 * @sim.resolution )
      # disconnect the spare pod
      rtr = @sim.item("a%dr1" % @podcnt)
      iface = rtr.get_iface(11)
      lnk = iface.link
      iface.unplug

      @extra_iface = iface
      @extra_link = lnk

      return 20 * @sim.resolution

   # 20s
   elsif( st == 20 * @sim.resolution )

      # disconnect a0r2 port 0
      rtr = @sim.item("a0r2")
      iface = rtr.get_iface(0)
      lnk = iface.link
      iface.unplug

      @main_iface = iface
      @main_link = lnk

      return 30 * @sim.resolution

   # 30s
   elsif( st == 30 * @sim.resolution )

      # reconnect a0r2 port 0
      @main_iface.plugin(@main_link)
      
      return 40 * @sim.resolution

   # 40s
   elsif( st == 40 * @sim.resolution )

      # disconnect a0r2 port 11
      rtr = @sim.item("a0r2")
      iface = rtr.get_iface(11)
      lnk = iface.link
      iface.unplug

      @main_iface = iface
      @main_link = lnk

      return 50 * @sim.resolution

   # 50s
   elsif( st == 50 * @sim.resolution )

      # reconnect a0r2 port 11
      @main_iface.plugin(@main_link)
      
      return 60 * @sim.resolution

   # 60s
   elsif( st == 60 * @sim.resolution )

      # plugin extra pod
      @extra_iface.plugin(@extra_link)
      
      return 70 * @sim.resolution

   else
      return Model::NEVER
   end

end # def sim_run()

end # class TEZC::Test::TestPods
end # module TEZC::Test
end # module TEZC



##########################################################################

# runtime
sim = TEZC::Model::Runtime.new(STDERR, :info, 1000000)

# setup customer address handling in the Info service
TEZC::Info::Customer.handle(:model, TEZC::Info::CustomerModel)

# build a topo
podcnt = ARGV[0].to_i
topo_spec = net_create(podcnt)

# create our topology
topo = TEZC::Test::Topologies.new(sim, 2)
topo.gen_specified('', topo_spec)

# finish the topo
topo.add_nis('')

# set all routers to log level trace
sim.items_each("", TEZC::Model::Router) do |rt|
   rt.sim_loglevel = :trace
end

# set all database to log level info
sim.items_each("", TEZC::Model::NIS) do |it|
   it.sim_loglevel = :info
end

# set the routing algorithm
file = File.open(ARGV[1], 'w')
algo = TEZC::Algorithm::AvoidCong.new(file)
TEZC::Model::RAS.set_algo(algo)


# make a single host for each pod
client_port = 14
gens = Array.new(podcnt+1)
gens.each_index do |pix|

   # generator & link
   gen = TEZC::Model::GenPackets.new(sim, "a%dg0" % pix)
   gens[pix] = gen
   lnk = TEZC::Model::Link.new(sim, "a%dg0k" % pix)

   # set generator port as a client
   rp = sim.item('a%dr0' % pix)
   rp.nis.cfg_client(client_port, true)

   # plugin
   gen.plugin(lnk.a)
   rp.get_iface(client_port).plugin(lnk.b)

   # set egress
   ri = rp.nis.service
   ri.set_egress(client_port, {type: :model, addr: [3, pix] })
   rp.nis.rule_set({type: :model, addr: [3, pix] }, :iface, client_port)

   # set demands
   gens.each_index do |pix_d|
      next if( pix_d == pix )
      ri.demand_set(pix*100+pix_d, {type: :model, addr: [3, pix_d]}, 4, 15000)
   end

end


#################################################
# simulate
cont = TEZC::Test::TestPods.new(sim, "test", gens, podcnt)
sim.simulate(sim.resolution * 2*60) 
