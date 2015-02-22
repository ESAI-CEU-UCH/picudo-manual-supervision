-- Copyright (c) 2015 Francisco Zamora-Martinez (francisco.zamora@uch.ceu.es)
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.

local common = require "scripts.common"
local cmd = require "scripts.cmdopt"
--
local MAX_LAYERS=5
--
local opt = cmd.new(arg, "Training of MLP for picudo dataset")
cmd.add_help(opt)
cmd.add_dataset(opt)
cmd.add_trainer(opt, MAX_LAYERS)
cmd.add_mlp(opt, MAX_LAYERS)
local global_hyps, layerwise_hyps = cmd.add_optimizer(opt)
cmd.add_save(opt)
--
local params  = cmd.parse(opt, arg)
opt = nil
local srandom = random(params.sseed)
local prandom = random(params.pseed)
local drandom = random(params.dseed)
--
local train,val,test = common.load_training_validation_test(params)
local train,val,test,mean_dev = common.standarize_train_validation_test(params,
                                                                        train,
                                                                        val,
                                                                        test)
local train      = common.contextualize(params, train)
local val        = common.contextualize(params, val)
local test       = common.contextualize(params, test)
local train_data = common.build_input_output_dataset_table(params, train, true)
local val_data   = common.build_input_output_dataset_table(params, val,   true)
local test_data  = common.build_input_output_dataset_table(params, test,  true)
print("# Pattern size=   ", train_data.input_dataset:patternSize())
print("# Num classes=    ", train_data.output_dataset:patternSize())
print("# Training patterns=   ", train_data.input_dataset:numPatterns())
print("# Validation patterns= ", val_data.input_dataset:numPatterns())
print("# Test patterns=       ", test_data.input_dataset:numPatterns())
--
train_data.input_dataset = common.perturbation_dataset(train_data.input_dataset,
                                                       params.var,
                                                       prandom)
train_data.shuffle     = srandom
train_data.replacement = params.bsize
val_data.bunch_size    = 512
test_data.bunch_size   = 512
--
local isize = train_data.input_dataset:patternSize()
local osize = train_data.output_dataset:patternSize()
--
local net = common.build_stacked_mlp(params, isize, osize, MAX_LAYERS)
--
local loss = ann.loss.cross_entropy()
local opt  = ann.optimizer[params.optimizer]()
--
local trainer = trainable.supervised_trainer(net, loss, params.bsize, opt,
                                             smooth, max_grad_norm)
trainer:build()
common.randomize_weights(trainer, math.sqrt(6), prandom)
common.set_bias(trainer, 0.0)
common.set_trainer_options(trainer, global_hyps, layerwise_hyps)
--
local best = common.mlp_training_loop(params, trainer,
                                      train_data, val_data, test_data)
common.save_result(params, best, mean_dev)


-- local best = best:clone()
-- local b1 = best:weights("b1")
-- local w1 = best:weights("w1")
-- -- local w = matrix(w1:dim(1)+1, w1:dim(2))
-- local input_ds = dataset.union(train.input_ds)

-- local X = matrix.join(2, matrix(input_ds:numPatterns(),1):ones(),
--                       input_ds:toMatrix())
-- local y = train_data.output_dataset:toMatrix()
-- local beta = (X * X:t()):inv() * X * y
-- print(beta)

-- print( common.compute_auc(best, val_data) )
