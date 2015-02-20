#!/bin/bash
train=lists/DATASETS/eating_upv.fb_24_mats.txt
val=$train
test=$train
april-ann scripts/TRAINING/train_mlp.lua --train=$train --val=$val --test=$test $@
