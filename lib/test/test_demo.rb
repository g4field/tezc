#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#
 
require_relative '../model/runtime'
require_relative '../model/gen_packets'
require_relative 'topologies'
require_relative '../algo/avoid_cong'

module TEZC
module Test

class TestDemo < Model::Item

def initialize(sim, name, gens)
   sim_register(sim, nil, name)
   sim_wake()

   @gens = gens
end # def initialize()

def sim_run(st)

   # wait until 5 s
   if( st < 20 * @sim.resolution )
      return 20 * @sim.resolution

   # 20s
   elsif( st == 20 * @sim.resolution )

      # trace, 1 packet ps, 1sec, send to next over
      @gens[0].trace(1, 300, [3, 2, 1], 1)

      return 21 * @sim.resolution

   # 21s
   elsif( st == 21 * @sim.resolution )

      # trace, 1 packet ps, 1sec, send to next over
      @gens[2].trace(1, 300, [3, 0, 0], 1)

      return 22 * @sim.resolution

   # 22s
   elsif( st == 22 * @sim.resolution )

      # trace, 1 packet ps, 1sec, send to next over
      @gens[4].trace(1, 300, [3, 1, 1], 1)

      return 23 * @sim.resolution

   # 23s
   elsif( st == 23 * @sim.resolution )

      # trace, 1 packet ps, 1sec, 
      @gens[1].trace(1, 300, [3, 1, 0], 1)

      return 24 * @sim.resolution

   else
      return Model::NEVER
   end

end # def sim_run()

end # class TEZC::Test::TestDemo
end # module TEZC::Test
end # module TEZC


desc_l1 = {

   # 4 identical routers
   routers: [
      {count: 4, spec: {ports: 4} },
   ],

   # full mesh links
   links: [
      ['r0', 0, 'r1', 1],
      ['r1', 0, 'r3', 1],
      ['r3', 0, 'r2', 1],
      ['r2', 0, 'r0', 1],

      ['r0', 2, 'r3', 2],
      ['r1', 2, 'r2', 2],
   ]
}

topo_spec =  {

   areas: [
      { count: 3, spec: desc_l1 },
   ],

   links: [
      ['a0r2', 3, 'a1r1', 3],
      ['a0r3', 3, 'a2r0', 3],
      ['a1r3', 3, 'a2r2', 3],
   ]
}

##########################################################################

# runtime
sim = TEZC::Model::Runtime.new(STDERR, :info, 1000000)

# setup customer address handling in the Info service
TEZC::Info::Customer.handle(:model, TEZC::Info::CustomerModel)

# create our topology
topo = TEZC::Test::Topologies.new(sim, 4)
topo.gen_specified('', topo_spec)

# finish the topo
topo.add_nis('')

# set all routers to log level trace
sim.items_each("", TEZC::Model::Router) do |rt|
   rt.sim_loglevel = :trace
end

# set all database to log level verbose
sim.items_each("", TEZC::Model::NIS) do |it|
   it.sim_loglevel = :info
end


hosts = [ [0, 1], [0, 2], [1, 3] ]

# add generators and links
gens = []
3.times do |xa|
   2.times do |xh|

      # generator & link
      gen = TEZC::Model::GenPackets.new(sim, "a%dh%d" % [xa, xh])
      gens.append(gen)
      lnk = TEZC::Model::Link.new(sim, "ga%dh%d" % [xa, xh])

      # set generator port as a client
      rp = sim.item('a%dr%d' % [xa, hosts[xa][xh]])
      rp.nis.cfg_client(3, true)

      # plugin
      gen.plugin(lnk.a)
      rp.get_iface(3).plugin(lnk.b)

      # set egress for each generator
      ri = rp.nis.service
      ri.set_egress(3, {type: :model, addr: [3, xa, xh] })
      rp.nis.rule_set({type: :model, addr: [3, xa, xh] }, :iface, 3)

      # set demands for each generator
      3.times do |ya|
         2.times do |yh|
            next if( ya == xa && yh == xh )
            ri.demand_set(ya*2+yh+1, {type: :model, addr: [3, ya, yh]}, 7, 15000)
         end
      end
   end
end

# set the routing algorithm
file = File.open(ARGV[0], 'w')
algo = TEZC::Algorithm::AvoidCong.new(file)
TEZC::Model::RAS.set_algo(algo)

#sim.item("a0r0:ni").sim_loglevel = :verbose

#################################################
# simulate
cont = TEZC::Test::TestDemo.new(sim, "test", gens)
sim.simulate(sim.resolution * 5*60) 

