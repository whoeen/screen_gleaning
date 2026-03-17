%% emage_preprocess.m
% Signal pre-processing helpers: low-pass filter and image normalisation.
% Converts the "Lowpass before sync" and image normalisation logic from
% Main.java and Recognition/utils.py into MATLAB functions.

%% ── Low-pass moving-average filter (Main.java menu "Lowpass before sync") ───

function y = lowpass_ma(x, M)
% lowpass_ma  Moving-average (box) low-pass filter.
%
%   y = lowpass_ma(x, M)
%
%   Equivalent to the Java pre-filter applied before autocorrelation:
%       y[n] = (1/M) Σ_{k=0}^{M-1} x[n-k]
%
%   H(z) = (1/M)·(1−z^{-M}) / (1−z^{-1})
%
%   x : 1-D signal vector
%   M : filter order (window length)

b = ones(1, M) / M;
y = filter(b, 1, double(x));
end


%% ── Per-device image normalisation (utils.py, lines 10-33) ──────────────────

function img_norm = normalise_emage(img, device)
% normalise_emage  Normalise a grayscale emage to match training statistics.
%
%   img_norm = normalise_emage(img, device)
%
%   img    : [H × W] or [H × W × 1] uint8 or double image
%   device : 'iph6' | 'iph6s' | 'honor' | 'eyedoctor'
%
%   Statistics from utils.py (Normalize transform):
%       iph6       μ=0.2933  σ=0.0546
%       iph6s      μ=0.1545  σ=0.0489
%       honor      μ=0.4303  σ=0.0315
%       eyedoctor  μ=0.2968  σ=0.1310
%
%   Formula: img_norm = (img_float − μ) / σ

stats = struct( ...
    'iph6',      [0.2933, 0.0546], ...
    'iph6s',     [0.1545, 0.0489], ...
    'honor',     [0.4303, 0.0315], ...
    'eyedoctor', [0.2968, 0.1310]);

if ~isfield(stats, device)
    error('normalise_emage: unknown device "%s". Use iph6|iph6s|honor|eyedoctor.', device);
end

mu  = stats.(device)(1);
sig = stats.(device)(2);

img_float = double(img);
if max(img_float(:)) > 1
    img_float = img_float / 255;
end

img_norm = (img_float - mu) / sig;
end


%% ── Digit patch extraction (utils.py: security_test, lines 114-150) ─────────

function patches = extract_digit_patches(img, device)
% extract_digit_patches  Crop 6 individual digit patches from a security-code emage.
%
%   patches = extract_digit_patches(img, device)
%
%   Resizes the emage to the device-specific code region and returns
%   a 1×6 cell array of single-digit patches.
%
%   Device crop sizes (utils.py):
%       iph6 / iph6s : resize to 120×31,  each digit = 20×31 px
%       honor        : resize to 126×45,  each digit = 21×45 px

switch lower(device)
    case {'iph6', 'iph6s'}
        total_w = 120;  h = 31;  dw = 20;    % 6 × 20 = 120
    case 'honor'
        total_w = 126;  h = 45;  dw = 21;    % 6 × 21 = 126
    otherwise
        error('extract_digit_patches: unknown device "%s".', device);
end

% Resize to canonical code-strip size
img_strip = imresize(img, [h, total_w], 'bilinear');
if size(img_strip, 3) > 1
    img_strip = rgb2gray(img_strip);
end

% Crop each digit
patches = cell(1, 6);
for k = 1:6
    x1 = (k-1)*dw + 1;
    x2 = k*dw;
    patches{k} = img_strip(:, x1:x2);   % [h × dw]
end
end


%% ── Parse ground-truth from filename (utils.py line 120) ────────────────────

function gt = parse_gt_filename(filename)
% parse_gt_filename  Extract 6-digit ground-truth from security-code filename.
%
%   Filenames follow the pattern  "D-D-D-D-D-D_<rest>.jpg"
%   e.g. "3-7-1-9-0-4_capture1.png"  →  gt = [3 7 1 9 0 4]

[~, name] = fileparts(filename);
parts = strsplit(name, '_');
digits_str = strsplit(parts{1}, '-');
gt = cellfun(@str2double, digits_str);
end
