%% security_code_test.m
% Security-code evaluation script.
% MATLAB port of Recognition/utils.py: security_test() and security_test_honor()
% and test_security_code.py.
%
% Evaluates digit-level and code-level accuracy on a test set.
%
% Usage:
%   [digit_acc, code_acc] = security_code_test(net, test_dir, device)
%
%   net      : trained dlnetwork / SeriesNetwork (from train_securitycode)
%   test_dir : folder with test PNG files named "D-D-D-D-D-D_*.png"
%   device   : 'iph6' | 'iph6s' | 'honor'

function [digit_acc, code_acc] = security_code_test(net, test_dir, device)

addpath(fullfile(fileparts(mfilename('fullpath'))));  % emage_preprocess

files = dir(fullfile(test_dir, '*.png'));
if isempty(files)
    files = dir(fullfile(test_dir, '*.jpg'));
end
if isempty(files)
    error('security_code_test: no images found in %s', test_dir);
end

correct_digits = 0;
total_digits   = 0;
correct_codes  = 0;
total_codes    = 0;

for i = 1:numel(files)
    fname = files(i).name;
    fpath = fullfile(test_dir, fname);

    %% ── Load and crop ─────────────────────────────────────────────────────
    img = imread(fpath);
    patches = extract_digit_patches(img, device);   % 1×6 cell

    %% ── Ground truth from filename ───────────────────────────────────────
    gt = parse_gt_filename(fname);                  % [1×6] int vector

    %% ── Predict each digit ───────────────────────────────────────────────
    pred = zeros(1, 6);
    for k = 1:6
        patch = patches{k};                     % [h × dw] uint8/double
        patch = normalise_emage(patch, device); % z-score
        patch = single(patch);

        % Add batch & channel dims → [h × dw × 1 × 1]
        if ndims(patch) == 2
            patch = reshape(patch, size(patch,1), size(patch,2), 1, 1);
        end

        scores = predict(net, patch);            % [1×10] class probabilities
        [~, idx] = max(scores, [], 2);
        pred(k) = idx - 1;                       % class index 1-based → 0-based digit
    end

    %% ── Accumulate metrics ───────────────────────────────────────────────
    digit_hits = sum(pred == gt);
    correct_digits = correct_digits + digit_hits;
    total_digits   = total_digits   + 6;

    correct_codes = correct_codes + (digit_hits == 6);
    total_codes   = total_codes   + 1;
end

digit_acc = correct_digits / total_digits * 100;
code_acc  = correct_codes  / total_codes  * 100;

fprintf('[security_code_test] Device: %s\n', device);
fprintf('  Digit accuracy : %.2f %%  (%d/%d)\n', digit_acc, correct_digits, total_digits);
fprintf('  Code  accuracy : %.2f %%  (%d/%d)\n', code_acc,  correct_codes,  total_codes);
end


%% ── Batch evaluation across all devices (test_security_code.py) ─────────────

function batch_evaluate(ckpt_dir, data_base, devices)
% batch_evaluate  Evaluate all device models on their respective test sets.
%
%   Mirrors test_security_code.py which tests iph6, iph6s, honor6x models.

if nargin < 3
    devices = {'iph6', 'iph6s', 'honor'};
end

for d = devices
    dev = d{1};
    switch dev
        case 'iph6'
            ckpt    = fullfile(ckpt_dir, 'secpin_iph6_best.mat');
            testdir = fullfile(data_base, 'iphone6/test');
        case 'iph6s'
            ckpt    = fullfile(ckpt_dir, 'secpin_iph6s_best.mat');
            testdir = fullfile(data_base, 'iphone6s/test');
        case 'honor'
            ckpt    = fullfile(ckpt_dir, 'secpin_honor_best.mat');
            testdir = fullfile(data_base, 'honor6x/test');
    end

    if ~exist(ckpt, 'file')
        fprintf('[batch_evaluate] Checkpoint not found: %s\n', ckpt);
        continue;
    end

    loaded = load(ckpt, 'net');
    security_code_test(loaded.net, testdir, dev);
end
end
