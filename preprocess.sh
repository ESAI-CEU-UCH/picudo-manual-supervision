#!/bin/bash
# python scripts/ANNOTATE/annotate.py lists/DATASETS/eating_upv.wavs.txt lists/DATASETS/eating_upv.infos.txt
# python scripts/ANNOTATE/generate_wav_mat.py lists/DATASETS/eating_upv.wavs.txt lists/DATASETS/eating_upv.wav_mats.txt
# april-ann scripts/PREPROCESS/preprocess.lua lists/DATASETS/eating_upv.wav_mats.txt lists/DATASETS/eating_upv.infos.txt lists/DATASETS/eating_upv.fb_24_mats.txt 24
april-ann scripts/PREPROCESS/preprocess.lua lists/DATASETS/eating_upv.wav_mats.txt lists/DATASETS/eating_upv.infos.txt lists/DATASETS/eating_upv.fb_12_mats.txt 12
