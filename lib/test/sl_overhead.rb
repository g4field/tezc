#!/usr/bin/env ruby
#
# Copyright 2026 by Graham A. Field
# All Rights Reserved
#

require_relative 'sim_linux_gen'

desc_l1 = {

   # 2 routers
   routers: 3,

   # full mesh links
   links: [
      ['r0', 'r1', 100000],
      ['r1', 'r2', 100000],
      ['r2', 'r0', 100000],
   ]
}

topo_spec =  {

   areas: [
      { count: 2, spec: desc_l1 },
   ],

   links: [
      ['a0r2', 'a1r2', 100000],
   ]
}

# name of this topology
dir = 'overhead'

# generate it
gen = TEZC::Test::SimLinuxGen.new
gen.gen_specified('', topo_spec)

pt0 = gen.host_add('a0h0', 'a0r0', '10.0.0.2', '10.0.0.1', 24, 100000)
pt2 = gen.host_add('a1h0', 'a1r0', '10.1.0.2', '10.1.0.1', 24, 100000)

pt1 = gen.host_add('a0h1', 'a0r1', '10.0.1.2', '10.0.1.1', 24, 100000)
pt3 = gen.host_add('a1h1', 'a1r1', '10.1.1.2', '10.1.1.1', 24, 100000)

gen.demand_add('a0r0', pt0, '10.1.0.2/32', 3, 50000)
gen.demand_add('a1r0', pt2, '10.0.0.2/32', 3, 50000)

gen.demand_add('a0r1', pt1, '10.1.1.2/32', 3, 50000)
gen.demand_add('a1r1', pt3, '10.0.1.2/32', 3, 50000)

gen.build(dir)