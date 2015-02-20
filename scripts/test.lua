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

local check = utest.check
local T     = utest.test
local common = require "scripts.common"

local FB_MATS_LIST = "lists/DATASETS/eating_upv.fb_12_mats.txt"
local PAT_SIZE     = 12
local BIN_PAT_SIZE = 1
local LBL_PAT_SIZE = 3

local in_ds, bin_ds, lbl_ds = common.load_dataset(FB_MATS_LIST)

local in_ds  = dataset.union(in_ds)
local bin_ds = dataset.union(bin_ds)
local lbl_ds = dataset.union(lbl_ds)

T("DatasetTest", function()
    check.eq(in_ds:patternSize(),  PAT_SIZE)
    check.eq(bin_ds:patternSize(), BIN_PAT_SIZE)
    check.eq(lbl_ds:patternSize(), LBL_PAT_SIZE)
    check.gt(bin_ds:toMatrix():sum(), 0)
    check.le(bin_ds:toMatrix():sum(), lbl_ds:toMatrix():sum())
end)

T("MeanAndDevs", function()
    common.normalize_mean_dev(in_ds, common.compute_mean_dev(in_ds))
    local mean,dev = table.unpack(common.compute_mean_dev(in_ds))
    mean,dev = matrix(mean),matrix(dev)
    check.eq( mean:rewrap(mean:size()), matrix(mean:size()):zeros() )
    check.eq( dev:rewrap(mean:size()), matrix(dev:size()):ones() )
end)
