#!/bin/bash
# Copyright 2021 Kanari AI (Amir Hussein)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

# This is the evaluation file for the finetuned Hi-En-CS model

. ./path.sh || exit 1;
. ./cmd.sh || exit 1;

model_dir= # finetuned model files directory
# general configuration
backend=pytorch
model='hi_cs'
stage=0    # start from -1 if you need to start from data download
stop_stage=3
ngpu=0         # number of gpus ("0" uses cpu, otherwise use gpu)
nj=300
debugmode=1
dumpdir=dump_$model  # directory to dump full features
N=0            # number of minibatches to be used (mainly for debugging). "0" uses all minibatches.
verbose=0      # verbose option
resume=        # Resume the training from snapshot
data_folder=data
# feature configuration
do_delta=false

preprocess_config=conf/specaug.yaml
train_config=conf/finetune.yaml # current default recipe requires 4 gpus.
                             # if you do not have 4 gpus, please reconfigure the `batch-bins` and `accum-grad` parameters in config.
lm_config=conf/lm_transformer.yaml
decode_config=conf/decode.yaml

# rnnlm related
lm_resume= # specify a snapshot file to resume LM training
lmtag=     # tag for managing LMs


# decoding parameter
recog_model=model.acc.best  # set a model to be used for decoding: 'model.acc.best' or 'model.loss.best'
lang_model=rnnlm.model.best # set a language model to be used for decoding

# model average realted (only for transformer)
n_average=3                 # the number of ASR models to be averaged
use_valbest_average=true     # if true, the validation `n_average`-best ASR models will be averaged.
                             # if false, the last `n_average` ASR models will be averaged.
lm_n_average=0               # the number of languge models to be averaged
use_lm_valbest_average=false # if true, the validation `lm_n_average`-best language models will be averaged.
                             # if false, the last `lm_n_average` language models will be averaged.
# Set this to somewhere where you want to put your data, or where
# someone else has already put it.  You'll want to change this
datadir=data

# bpemode (unigram or bpe)
bpemode=unigram
# exp tag
tag="" # tag for managing experiments.

. utils/parse_options.sh || exit 1;

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -o pipefail

#train_dev=test
recog_set="blind"

# loading the model with its related files

if [ $model == 'bn_cs' ]; then
	rec_model=models/${model}/model.val3.avg.best
	nbpe=1000
	dict=$model/train_unigram${nbpe}_units.txt
	bpemodel=$model/train_unigram${nbpe}
	cmvn=models/${model}/${cmvn.ark}
elif [ $model == 'hi_cs' ]; then
	rec_model=models/${model}/model.val3.avg.best
	nbpe=1000 
	dict=$model/train_unigram${nbpe}_units.txt
	bpemodel=$model/train_unigram${nbpe}
	cmvn=models/${model}/${cmvn.ark}
	
#feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
feat_ts_dir=${dumpdir}/test/delta${do_delta}; mkdir -p ${feat_ts_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    ### Task dependent. You have to design training and dev sets by yourself.
    ### But you can utilize Kaldi recipes in most cases
    echo "stage 1: Feature Generation"
    
    fbankdir=fbank_$model
    # Generate the fbank features; by default 80-dimensional fbanks with pitch on each frame
    for x in $recog_set; do
        utils/fix_data_dir.sh $data_folder/$x
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj ${nj} --write_utt2num_frames true \
            $data_folder/${x} exp/make_fbank/${x} ${fbankdir}
        utils/fix_data_dir.sh $data_folder/${x}
    done
    
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}; mkdir -p ${feat_recog_dir}
        dump.sh --cmd "$train_cmd" --nj ${nj} --do_delta ${do_delta} \
            $data_folder/${rtask}/feats.scp $cmvn exp/dump_feats/recog/${rtask} \
            ${feat_recog_dir}
    done
fi

echo "dictionary: ${dict}"
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then


    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        data2json.sh --nj ${nj} --feat ${feat_recog_dir}/feats.scp --bpecode ${bpemodel}.model \
            $data_folder/${rtask} ${dict} > ${feat_recog_dir}/data_${bpemode}${nbpe}.json
    done
fi

if [ -z ${tag} ]; then
    expname=${backend}_$(basename ${train_config%.*})_final
    if ${do_delta}; then
        expname=${expname}_delta
    fi
    if [ -n "${preprocess_config}" ]; then
        expname=${expname}_$(basename ${preprocess_config%.*})
    fi
else
    expname=${backend}_${tag}
fi
expdir=exp/${expname}

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    echo "stage 3: Decoding"

    pids=() # initialize pids
    for rtask in ${recog_set}; do
    (
        decode_dir=decode_${rtask}_${recog_model}_$(basename ${decode_config%.*})_blind
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}

        # split data
        splitjson.py --parts ${nj} ${feat_recog_dir}/data_${bpemode}${nbpe}.json

        #### use CPU for decoding
        ngpu=0

        # set batchsize 0 to disable batch decoding
        ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            asr_recog.py \
            --config ${decode_config} \
            --ngpu ${ngpu} \
            --backend ${backend} \
            --batchsize 0 \
            --recog-json ${feat_recog_dir}/split${nj}utt/data_${bpemode}${nbpe}.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model $rec_model  \
            --api v2

        score_sclite.sh --bpe ${nbpe} --bpemodel ${bpemodel}.model --wer true ${expdir}/${decode_dir} ${dict}
        python local/trn2text.py ${expdir}/${decode_dir}/hyp.wrd.trn ${expdir}/${decode_dir}/hyp.tra
        cat ${expdir}/${decode_dir}/hyp.tra | cut -d "-" -f2- > ${model}.txt
    ) &
    pids+=($!) # store background pids
    done
    i=0; for pid in "${pids[@]}"; do wait ${pid} || ((++i)); done
    [ ${i} -gt 0 ] && echo "$0: ${i} background jobs are failed." && false
    echo "Finished"
fi
