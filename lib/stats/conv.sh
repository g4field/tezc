#!/bin/bash


echo "running model"
time ./test/test_pods.rb $1 rt.tsv 2> pods-$1-overview.tsv

echo "checking convergence"
mv logs logs-$1
./stats/conv.rb logs-$1 > pods-$1-conv.txt

echo "archiving logs"
tar cJf pods-$1-logs.tar.xz logs-$1
rm -r logs-$1
