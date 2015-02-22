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

local common = {} -- exported table

function common.extract_datasets_from_matrix(data)
  collectgarbage("collect")
  local current_fb_len = data:dim(2) - 4
  FB_LEN = FB_LEN or current_fb_len
  assert(current_fb_len == FB_LEN) -- sanity check
  local spec_pat_size = { 1, current_fb_len }
  local bin_cls_pat_size = { 1, 1 }
  local bin_cls_offset   = { 0, current_fb_len }
  local multi_lbl_cls_pat_size = { 1, 3 }
  local multi_lbl_cls_offset   = { 0, current_fb_len+1 }
  --
  local ds_mat = dataset.matrix -- alias
  local spec_ds  = ds_mat(data, { patternSize=spec_pat_size })
  local bin_cls_ds    = ds_mat(data, { patternSize=bin_cls_pat_size,
                                       offset=bin_cls_offset })
  local multi_lbl_ds  = ds_mat(data, { patternSize=multi_lbl_cls_pat_size,
                                       offset=multi_lbl_cls_offset })
  return spec_ds, bin_cls_ds, multi_lbl_ds
end

-- receives a list with filter bank data + class labels, and returns three
-- datasets: the input dataset, the binary classification output dataset, the
-- multilabel classification output dataset (3 classes, start, middle, stop)
function common.load_dataset(fb_mats_list)
  assert(fb_mats_list, "Needs a filename as argument")
  local FB_LEN
  local ds_tbl = iterator(io.lines(fb_mats_list)):
    map(matrix.fromFilename):
    map(common.extract_datasets_from_matrix):
    map(table.pack):
    table()
  local input_ds = iterator(ds_tbl):field(1):table()
  local bin_output_ds = iterator(ds_tbl):field(2):table()
  local multi_label_output_ds = iterator(ds_tbl):field(3):table()
  local function numPatterns(ds_tbl)
    return iterator(ds_tbl):map(dataset.."numPatterns"):sum()
  end
  assert(numPatterns(input_ds) == numPatterns(bin_output_ds))
  assert(numPatterns(input_ds) == numPatterns(multi_label_output_ds))
  return input_ds, bin_output_ds, multi_label_output_ds
end

-- receives a dataset and returns a table with mean/devs needed by
-- common.normalize_mean_dev to normalize a dataset
function common.compute_mean_dev(ds_tbl)
  local ds = dataset.union(ds_tbl)
  return table.pack( ds:mean_deviation() )
end

-- receives a dataset and a table returned by common.compute_mean_dev and
-- normalizes the given dataset to be zero-mean one-variance.
function common.normalize_mean_dev(ds_tbl, mean_devs)
  for _,ds in ipairs(ds_tbl) do
    ds:normalize_mean_deviation( table.unpack(mean_devs) )
  end
end

function common.standarize_train_validation_test(params, train, val, test)
  local mean_devs = params.mean_devs or common.compute_mean_dev(train.input_ds)
  common.normalize_mean_dev(train.input_ds, mean_devs)
  common.normalize_mean_dev(val.input_ds,   mean_devs)
  common.normalize_mean_dev(test.input_ds,  mean_devs)
  return train,val,test,mean_devs
end

function common.contextualize(params, tbl)
  if params.context and params.context > 0 then
    local ds_tbl = tbl.input_ds
    for i,ds in ipairs(ds_tbl) do
      ds_tbl[i] = dataset.contextualizer(ds, params.context, params.context)
    end
  end
  return tbl
end

-- receives three filename lists (optionally they can be nil), and returns three
-- tables with input_ds, bin_output_ds and lbl_output_ds datasets for training,
-- validation and test
function common.load_training_validation_test(params)
  local train,val,test = params.train, params.val, params.test
  local psize
  if train then
    print("# Loading training")
    train = table.pack(common.load_dataset(train))
    psize = train[1][1]:patternSize()
  end
  if val then
    print("# Loading validation")
    val = table.pack(common.load_dataset(val))
    psize = psize or val[1][1]:patternSize()
  end
  if test then
    print("# Loading test")
    test = table.pack(common.load_dataset(test))
    psize = psize or test[1][1]:patternSize()
  end
  --
  local function check_psize(t)
    assert(not t or psize == t[1][1]:patternSize())
  end
  check_psize(train)
  check_psize(val)
  check_psize(test)
  --
  local function to_table(t)
    return t and { input_ds = t[1], bin_output_ds = t[2], lbl_output_ds = t[3] } or nil
  end
  return to_table(train), to_table(val), to_table(test)
end

function common.build_input_output_dataset_table(params, tbl, union)
  local output_ds = params.multi and tbl.lbl_output_ds or tbl.bin_output_ds
  local result = { input_dataset = tbl.input_ds, output_dataset = output_ds }
  if union then
    result.input_dataset = dataset.union(result.input_dataset)
    result.output_dataset = dataset.union(result.output_dataset)
  end
  return result
end

function common.perturbation_dataset(ds, var, rnd)
  if var > 0.0 then
    return dataset.perturbation{ dataset = ds,
                                 variance = var,
                                 mean = 0.0,
                                 random = rnd, }
  else
    return ds
  end
end

function common.build_stacked_mlp(params, isize, osize, MAX_LAYERS)
  local net = ann.components.stack()
  for i=1,MAX_LAYERS do
    local v = params["h%d"%{i}]
    if v == 0 then break end
    print("# Layer %d with size %d"%{ i, v })
    net:push( ann.components.hyperplane{ input = isize,
                                         output = v,
                                         bias_weights = "b%d"%{i},
                                         dot_product_weights = "w%d"%{i}, } )
    net:push( ann.components.actf[params.actf]() )
    if params.dropout > 0.0 then
      print("# Dropout %.2f", params.dropout)
      net:push( ann.components.dropout{ prob=params.dropout,
                                        random=drandom,
                                        value=params.dropout_mask, } )
    end
    isize = v
  end
  -- output layer
  net:push( ann.components.hyperplane{ input = isize,
                                       output = osize,
                                       bias_weights = "bN",
                                       dot_product_weights = "wN" } )
  net:push( ann.components.actf.log_logistic() )
  return net
end

function common.randomize_weights(trainer, threshold, prandom)
  threshold = threshold or math.sqrt(6)
  trainer:randomize_weights{
    name_match = "w.*",
    inf = -threshold,
    sup =  threshold,
    use_fanin = true,
    use_fanout = true,
    random = prandom,
  }
end

function common.set_bias(trainer, value)
  value = value or 0.0
  for _,b in trainer:iterate_weights("b.*") do b:fill(value) end
end

function common.set_trainer_options(trainer, global_hyps, layerwise_hyps)
  for name,value in pairs(global_hyps) do
    print("# Global option: ", name, value)
    trainer:set_option(name, value)
  end
  for layer,pair in pairs(layerwise_hyps) do
    print("# Layerwise option: ", layer, table.unpack(pair))
    trainer:set_layerwise_option(layer, table.unpack(pair))
  end
end

-- print the max norm2 of all the weights matrices
function common.print_weights_norm2(trainer, name)
  local mapf = function(name,w) return "%7.3f"%{trainer:norm2(name)} end
  return iterator(trainer:iterate_weights(name)):map(mapf):concat(" ", " ")
end

function common.compute_auc(trainer, data)
  local out = trainer:calculate(data.input_dataset:toMatrix()):exp()
  local tgt = data.output_dataset:toMatrix()
  local roc = metrics.roc(out,tgt)
  -- local curve = roc:compute_curve()
  -- curve:toTabFilename("curve")
  return roc:compute_area()
end

function common.mlp_training_loop(params, trainer, train_data,
                                  val_data, test_data)
  print("# Model size=", trainer:size())
  local pocket = trainable.train_holdout_validation{
    stopping_criterion = trainable.stopping_criteria.make_max_epochs_wo_imp_relative(2.0),
    min_epochs = params.min,
    max_epochs = params.max,
  }
  local pocket_train = function()
    local tr_loss = trainer:train_dataset(train_data)
    local va_loss = trainer:validate_dataset(val_data)
    return trainer,tr_loss,va_loss
  end
  -- TRAINING MAIN LOOP --
  while pocket:execute(pocket_train) do
    print(pocket:get_state_string(),
          "|w|= "..common.print_weights_norm2(trainer, "w.*"),
          "|b|= "..common.print_weights_norm2(trainer, "b.*"),
          "nump= " .. trainer:get_optimizer():get_count())
    io.stdout:flush()
  end
  ------------------------
  local state = pocket:get_state_table()
  local best  = state.best
  local va_loss,te_loss
  if train_data.output_dataset:patternSize() == 1 then
    va_loss = common.compute_auc(best, val_data)
    te_loss = common.compute_auc(best, test_data)
  else
    va_loss = best:validate_dataset(val_data)
    te_loss = best:validate_dataset(test_data)
  end
  --
  print(va_loss, te_loss)
  -- local out = best:calculate( val_data.input_dataset:toMatrix() ):exp()
  -- local out = matrix.join(2, out, val_data.output_dataset:toMatrix())
  -- out:toTabFilename("out")
  return best
end

function common.mkdir(path)
  os.execute("mkdir -p %s 2> /dev/null"%{ path })
end

function common.save_result(params, best, mean_dev)
  if params.dest then
    common.mkdir(params.dest:dirname())
    util.serialize({ mean_dev=mean_dev, model=best }, params.dest)
  end
end

return common
