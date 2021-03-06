#!/bin/bash


# Switch to script directory
cd `dirname -- "$0"`

if [ -z "$1" ]; then
  echo "Please enter DataSet, e.g. ./run spiral"
  exit 0
else
  DATA=$1
  shift
fi

if [ "$DATA" == "spiral" ]; then
  th main.lua -dataSet spiral -visualise2D 1 -xSize 2 -wSize 2 \
  -continuous 1 -hiddenSize 100 -K 8 -cvWeight 2.0 -batchSize 200 \
  -epoch 500 -seed 1 "$@"

elif [ "$DATA" == "mnist" ]; then
  th main.lua -ACC 1 -visualGen 1 -K 14 -batchSize 50 -inputDimension 2 \
  -network conv -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "mnist_fc" ]; then
  th main.lua -ACC 1 -visualGen 1 -K 14 -hiddenSize 1000 -batchSize 50 \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "fashion-mnist-fc" ]; then
  th main.lua -dataSet fashion-mnist -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 10 -batchSize 50 -inputDimension 1 -network fc \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "stl-10" ]; then
  th main.lua -dataSet stl-10 -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 10 -batchSize 50 -inputDimension 1 -network fc \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "cifar-10" ]; then
  th main.lua -dataSet cifar-10 -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 10 -batchSize 50 -inputDimension 1 -network fc \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "cifar-100" ]; then
  th main.lua -dataSet cifar-100 -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 100 -batchSize 50 -inputDimension 1 -network fc \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "svhn" ]; then
  th main.lua -dataSet svhn -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 10 -batchSize 50 -inputDimension 1 -network fc \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

elif [ "$DATA" == "fashion-mnist" ]; then
  th main.lua -dataSet fashion-mnist -continuous 1 -hiddenSize 1000 \
  -ACC 1 -K 10 -batchSize 50 -inputDimension 2 -network conv \
  -xSize 200 -wSize 150 -cvWeight 0.4 "$@"

fi
