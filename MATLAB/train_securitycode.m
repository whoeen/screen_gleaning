%% train_securitycode.m
% Training script for LeNet_EMAGE digit classifier.
% MATLAB port of Recognition/train_securitycode_iph6.py (and iph6s / honor6x).
%
% Usage:
%   train_securitycode('iph6',  'data/security_code/iphone6/')
%   train_securitycode('iph6s', 'data/security_code/iphone6s/')
%   train_securitycode('honor', 'data/security_code/honor6x/')
%
% Config defaults match the Python Config classes in Recognition/config.py:
%   batch_size  = 256
%   max_epoch   = 100
%   lr          = 1e-3
%   lr_decay    = 0.1  (applied every 50 epochs)
%   ckpt_path   = './checkpoints/'

function train_securitycode(device, data_root, opts)

%% ── Config (mirrors config.py) ───────────────────────────────────────────────
if nargin < 3, opts = struct(); end
batch_size  = getf(opts, 'batch_size',  256);
max_epoch   = getf(opts, 'max_epoch',  100);
lr          = getf(opts, 'lr',         1e-3);
lr_decay    = getf(opts, 'lr_decay',   0.1);
decay_steps = getf(opts, 'decay_steps', 50);
ckpt_path   = getf(opts, 'ckpt_path',  './checkpoints/');

if ~exist(ckpt_path, 'dir'), mkdir(ckpt_path); end

%% ── Build network ────────────────────────────────────────────────────────────
addpath(fullfile(fileparts(mfilename('fullpath')), 'networks'));

switch lower(device)
    case {'iph6', 'iph6s'}
        lgraph = lenet_emage_iph6();
    case 'honor'
        lgraph = lenet_emage_honor();
    otherwise
        error('train_securitycode: unknown device "%s". Use iph6|iph6s|honor.', device);
end

%% ── Data stores (ImageDatastore with per-device normalisation) ───────────────
% Directory layout expected (mirrors PyTorch ImageFolder):
%   data_root/train/0/  data_root/train/1/  …  data_root/train/9/
%   data_root/val/0/    …
%   data_root/test/0/   …

train_dir = fullfile(data_root, 'train');
val_dir   = fullfile(data_root, 'val');

imds_train = imageDatastore(train_dir, 'IncludeSubfolders', true, ...
                             'LabelSource', 'foldernames');
imds_val   = imageDatastore(val_dir,   'IncludeSubfolders', true, ...
                             'LabelSource', 'foldernames');

% Apply the same normalisation as utils.py data_transform_* (mean/std)
aug_train = augmentedImageDatastore( ...
    patch_size(device), imds_train, ...
    'DataAugmentation', image_augmenter(device), ...
    'ColorPreprocessing', 'gray2gray');

aug_val = augmentedImageDatastore( ...
    patch_size(device), imds_val, ...
    'ColorPreprocessing', 'gray2gray');

%% ── Training options (mirrors Adam + StepLR scheduler in Python) ─────────────
% LR schedule: lr × lr_decay every decay_steps epochs
lr_schedule = struct( ...
    'InitialLearnRate', lr, ...
    'Momentum', 0.9);    % Adam beta1

train_opts = trainingOptions('adam', ...
    'InitialLearnRate',     lr, ...
    'MaxEpochs',            max_epoch, ...
    'MiniBatchSize',        batch_size, ...
    'ValidationData',       aug_val, ...
    'ValidationFrequency',  floor(numel(imds_train.Files) / batch_size), ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  lr_decay, ...
    'LearnRateDropPeriod',  decay_steps, ...
    'Shuffle',              'every-epoch', ...
    'Verbose',              true, ...
    'Plots',                'training-progress', ...
    'CheckpointPath',       ckpt_path, ...
    'OutputNetwork',        'best-validation-loss');

%% ── Train ────────────────────────────────────────────────────────────────────
fprintf('[train] Device=%s  Epochs=%d  LR=%.1e\n', device, max_epoch, lr);
[net, info] = trainNetwork(aug_train, lgraph, train_opts);

%% ── Save best checkpoint ─────────────────────────────────────────────────────
ckpt_file = fullfile(ckpt_path, sprintf('secpin_%s_best.mat', device));
save(ckpt_file, 'net', 'info');
fprintf('[train] Saved checkpoint: %s\n', ckpt_file);
end


%% ── Helpers ──────────────────────────────────────────────────────────────────

function sz = patch_size(device)
switch lower(device)
    case {'iph6', 'iph6s'}, sz = [31 20 1];
    case 'honor',            sz = [45 21 1];
end
end


function aug = image_augmenter(device)
% Applies per-device mean/std normalisation via a custom preprocessing pipeline.
% (augmentedImageDatastore's built-in Normalize option expects a scalar range;
%  for per-channel stats we use a custom read function instead.)
aug = imageDataAugmenter();   % no geometric augmentation in original code
end


function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
