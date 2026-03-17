%% train_eyedoctor.m
% Training script for ResNet-18 eye-doctor letter classifier.
% MATLAB port of Recognition/train_eyedoctor.py.
%
% Usage:
%   train_eyedoctor('data/eyedoctor/T4/')
%
% Config (mirrors Config_eyedoctor in config.py):
%   model      = resnet18
%   batch_size = 256
%   max_epoch  = 25
%   lr         = 1e-4
%   classes    = C D E F L N O P T Z  (10 Sloan letters)

function train_eyedoctor(data_root, opts)

if nargin < 2, opts = struct(); end
batch_size = getf(opts, 'batch_size', 256);
max_epoch  = getf(opts, 'max_epoch',  25);
lr         = getf(opts, 'lr',         1e-4);
ckpt_path  = getf(opts, 'ckpt_path', './checkpoints/');

if ~exist(ckpt_path, 'dir'), mkdir(ckpt_path); end

addpath(fullfile(fileparts(mfilename('fullpath')), 'networks'));

%% ── Network ──────────────────────────────────────────────────────────────────
lgraph = resnet18_eyedoctor();

%% ── Data (224×224 RGB, normalised μ=0.2968, σ=0.1310) ───────────────────────
mu  = 0.2968 * 255;
sig = 0.1310 * 255;

imds_train = imageDatastore(fullfile(data_root, 'train'), ...
                             'IncludeSubfolders', true, 'LabelSource', 'foldernames');
imds_val   = imageDatastore(fullfile(data_root, 'val'),   ...
                             'IncludeSubfolders', true, 'LabelSource', 'foldernames');

aug_train = augmentedImageDatastore([224 224 3], imds_train);
aug_val   = augmentedImageDatastore([224 224 3], imds_val);

%% ── Training options ─────────────────────────────────────────────────────────
train_opts = trainingOptions('adam', ...
    'InitialLearnRate',    lr, ...
    'MaxEpochs',           max_epoch, ...
    'MiniBatchSize',       batch_size, ...
    'ValidationData',      aug_val, ...
    'ValidationFrequency', floor(numel(imds_train.Files) / batch_size), ...
    'Shuffle',             'every-epoch', ...
    'Verbose',             true, ...
    'Plots',               'training-progress', ...
    'CheckpointPath',      ckpt_path, ...
    'OutputNetwork',       'best-validation-loss');

%% ── Train ────────────────────────────────────────────────────────────────────
fprintf('[train_eyedoctor] Epochs=%d  LR=%.1e\n', max_epoch, lr);
[net, info] = trainNetwork(aug_train, lgraph, train_opts);

ckpt_file = fullfile(ckpt_path, 'eyed_best.mat');
save(ckpt_file, 'net', 'info');
fprintf('[train_eyedoctor] Saved: %s\n', ckpt_file);
end


%% ── Evaluation (mirrors evaluate() in utils.py:35-48) ───────────────────────

function acc = evaluate_eyedoctor(net, test_dir)
% evaluate_eyedoctor  Report top-1 accuracy on eye-doctor test images.

imds = imageDatastore(test_dir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
aug  = augmentedImageDatastore([224 224 3], imds);

pred_labels = classify(net, aug);
true_labels = imds.Labels;

acc = mean(pred_labels == true_labels) * 100;
fprintf('[evaluate_eyedoctor] Accuracy: %.2f %%\n', acc);
end


function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
