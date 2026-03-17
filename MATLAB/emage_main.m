%% emage_main.m
% EMAGE pipeline entry point.
% Ties together all MATLAB modules converted from the original Java/Python code.
%
% ┌─────────────────────────────────────────────────────────────────────────┐
% │  EMAGE pipeline (3 phases)                                              │
% │                                                                         │
% │  Phase 1 – CAPTURE (Automation)                                         │
% │    SDR samples → detect_sync → reconstruct_frame → process_frame        │
% │    → resize_frame → save PNG                                            │
% │                                                                         │
% │  Phase 2 – TRAIN (Recognition)                                          │
% │    PNG dataset → normalise → LeNet_EMAGE → train → checkpoint           │
% │                                                                         │
% │  Phase 3 – EVALUATE                                                     │
% │    checkpoint → extract_digit_patches → predict → accuracy              │
% └─────────────────────────────────────────────────────────────────────────┘
%
% Usage:
%   emage_main         % interactive mode: prompts for phase selection
%   emage_main(1)      % run Phase 1 (capture demo)
%   emage_main(2)      % run Phase 2 (train)
%   emage_main(3)      % run Phase 3 (evaluate)
%   emage_main([1,3])  % run capture then evaluate

function emage_main(phases)

%% ── Add sub-paths ────────────────────────────────────────────────────────────
base = fileparts(mfilename('fullpath'));
addpath(base);
addpath(fullfile(base, 'networks'));

if nargin == 0
    phases = input('[emage_main] Select phases to run [1=Capture 2=Train 3=Eval, e.g. [1,3]]: ');
end

for ph = phases(:)'
    switch ph
        case 1, run_capture(base);
        case 2, run_train(base);
        case 3, run_eval(base);
        otherwise, warning('emage_main: unknown phase %d', ph);
    end
end
end


%% ════════════════════════════════════════════════════════════════════════════
%  Phase 1 – CAPTURE demo
%  Demonstrates the full SDR → 2D reconstruction pipeline on a synthetic signal.
%% ════════════════════════════════════════════════════════════════════════════

function run_capture(base)
fprintf('\n══ Phase 1: Capture (simulation demo) ══\n');

%% Parameters (defaults from Main.java)
fs       = 2.4e6;    % SDR sample rate  [Hz]
fps_true = 25;       % display frame rate
H_true   = 625;      % display height   [lines]
gain     = 0.8;
mblur    = 0.6;
out_w    = 576;

%% Simulate one frame of EM signal
%  x[n] = periodic sync pulse train + noise
N_frame = round(fs / fps_true);
N_line  = round(N_frame / H_true);
n       = 0:N_frame*4-1;

% Impulse at every line start (simulates horizontal sync)
x = zeros(size(n));
x(mod(n, N_line) == 0) = 1;
x = x + 0.1 * randn(size(x));

%% Optional lowpass before sync detection
x_lp = lowpass_ma(x, 5);

%% Detect synchronisation
[fps_det, H_det, ok] = detect_sync(x_lp, fs);
if ~ok
    fprintf('[capture] Sync detection failed – using true values\n');
    fps_det = fps_true;
    H_det   = H_true;
end
fprintf('[capture] Detected  fps=%.2f  height=%.1f\n', fps_det, H_det);

%% Reconstruct one 2D frame
one_frame = x(1:N_frame);
img_raw   = reconstruct_frame(one_frame, fps_det, H_det, fs);

%% Process: gain + motion blur (first frame → no prev)
img_proc  = process_frame(img_raw, [], gain, mblur);

%% Resize to target width
img_final = resize_frame(img_proc, out_w);

%% Save
out_dir = fullfile(base, 'out');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end
fname = fullfile(out_dir, 'demo_capture.png');
imwrite(img_final, fname);
fprintf('[capture] Saved demo frame → %s\n', fname);

%% Display
figure('Name', 'Captured Frame');
imshow(img_final, []);
title(sprintf('Reconstructed frame  (fps=%.1f  H=%d  out_w=%d)', fps_det, round(H_det), out_w));
end


%% ════════════════════════════════════════════════════════════════════════════
%  Phase 2 – TRAIN
%% ════════════════════════════════════════════════════════════════════════════

function run_train(base)
fprintf('\n══ Phase 2: Train ══\n');

device    = input('[train] Device? (iph6 / iph6s / honor / eyedoctor): ', 's');
data_root = input('[train] Data root directory: ', 's');

switch lower(device)
    case {'iph6', 'iph6s', 'honor'}
        train_securitycode(device, data_root);
    case 'eyedoctor'
        train_eyedoctor(data_root);
    otherwise
        error('run_train: unknown device "%s"', device);
end
end


%% ════════════════════════════════════════════════════════════════════════════
%  Phase 3 – EVALUATE
%% ════════════════════════════════════════════════════════════════════════════

function run_eval(base)
fprintf('\n══ Phase 3: Evaluate ══\n');

ckpt_dir  = fullfile(base, 'checkpoints');
data_base = input('[eval] Data base directory (contains iphone6/ iphone6s/ honor6x/): ', 's');

batch_evaluate(ckpt_dir, data_base, {'iph6', 'iph6s', 'honor'});
end
