%% tsdr_dsp.m
% Full TempestSDR C-library DSP pipeline converted to MATLAB.
% Covers dsp.c, fft.c, frameratedetector.c, syncdetector.c.
%
% Function list (in pipeline order):
%
%   ── Stage 1: Auto-gain normalisation ─────────────────────────────────────
%   [x_norm, ag] = dsp_autogain_run(x, ag)          dsp.c
%
%   ── Stage 2: FFT-based autocorrelation (Wiener-Khinchin) ─────────────────
%   R          = fft_autocorrelation(x)              fft.c
%   [fps, H]   = frameratedetector_run(R, fs, opts)  frameratedetector.c
%
%   ── Stage 3: Sync detection & 2-D frame alignment ────────────────────────
%   [proj_h, proj_v] = dsp_average_v_h(frame, W, H)        dsp.c
%   [dx, fit_x]      = findbestfit(proj, strip_size)        syncdetector.c
%   img_aligned      = syncdetector_run(img_raw, dx, dy)    syncdetector.c
%   [fps, pll]       = frameratepll(pll, dx, fps)           syncdetector.c
%
%   ── Stage 4: Temporal averaging (Motion Blur / SNR) ──────────────────────
%   img_out = dsp_timelowpass_run(img_raw, img_prev, alpha) dsp.c
%
%   ── Full pipeline wrapper ────────────────────────────────────────────────
%   [img, state] = tsdr_pipeline(x, state)
%
% Dependencies: Signal Processing Toolbox (fft, ifft)
%               Image Processing Toolbox  (circshift)

%% ════════════════════════════════════════════════════════════════════════════
%  Stage 1 — Auto-gain (dsp.c : dsp_autogain_run)
%% ════════════════════════════════════════════════════════════════════════════

function [x_norm, ag] = dsp_autogain_run(x, ag)
% dsp_autogain_run  Per-frame EMA min/max normalisation.
%
%   [x_norm, ag] = dsp_autogain_run(x, ag)
%
%   x    : raw SDR samples (1-D real vector)
%   ag   : autogain state struct (pass [] for first call)
%          fields: lastmin, lastmax, snr
%
%   Maths (dsp.c):
%       min̂[t] = (1−α)·min̂[t−1] + α·min(x)
%       max̂[t] = (1−α)·max̂[t−1] + α·max(x)
%       x_norm = (x − min̂) / (max̂ − min̂)
%       SNR    = μ / σ

NORM_ALPHA = 0.1;   % EMA coefficient for min/max tracking

x = double(x(:));

% Initialise state on first call
if isempty(ag)
    ag.lastmin = min(x);
    ag.lastmax = max(x);
    ag.snr     = 0;
end

% Frame min/max
frame_min = min(x);
frame_max = max(x);

% EMA update
ag.lastmin = (1 - NORM_ALPHA) * ag.lastmin + NORM_ALPHA * frame_min;
ag.lastmax = (1 - NORM_ALPHA) * ag.lastmax + NORM_ALPHA * frame_max;

span = ag.lastmax - ag.lastmin;
if span < 1e-10
    x_norm = zeros(size(x));
    ag.snr = 0;
    return
end

% Normalise to [0, 1]
x_norm = (x - ag.lastmin) / span;

% SNR = mean / std  (dsp.c)
mu = mean(x_norm);
sg = std(x_norm);
ag.snr = mu / max(sg, 1e-10);
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 2a — FFT autocorrelation via Wiener-Khinchin (fft.c)
%% ════════════════════════════════════════════════════════════════════════════

function R = fft_autocorrelation(x)
% fft_autocorrelation  Compute one-sided autocorrelation using the
%                      Wiener-Khinchin theorem (O(n log n)).
%
%   R = fft_autocorrelation(x)
%
%   Algorithm (fft.c : fft_autocorrelation):
%     1) x[n] → zero-pad to next power of 2
%     2) X[k] = FFT{x[n]}
%     3) S[k] = |X[k]|       (power spectrum, magnitude only — matches C code)
%     4) R[τ] = IFFT{S[k]}   (Wiener-Khinchin)
%     5) Keep lags 0 … N-1   (one-sided, real part)

x = double(x(:));
N = length(x);

% Zero-pad to next power of 2  (fft_getrealsize in fft.c)
nfft = 2^nextpow2(2*N - 1);

% FFT
X = fft(x, nfft);

% Power spectrum: |X[k]|  (fft_complex_to_absolute_complex uses magnitude)
S = abs(X);

% IFFT → autocorrelation
r = real(ifft(S, nfft));

% One-sided, length N
R = r(1:N);
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 2b — Cumulative averaging of autocorrelation (frameratedetector.c)
%% ════════════════════════════════════════════════════════════════════════════

function [R_avg, acc] = accummulate(R, acc)
% accummulate  Running average of autocorrelation magnitude.
%
%   [R_avg, acc] = accummulate(R, acc)
%
%   acc : accumulator state struct (pass [] for first call)
%         fields: R_sum, count
%
%   Maths (frameratedetector.c):
%       R̄[τ] = (R̄[τ]·(N−1) + R[τ]) / N
%   In the C code each call computes sqrt(I²+Q²) then running average.

if isempty(acc)
    acc.R_sum = zeros(size(R));
    acc.count = 0;
end

acc.count = acc.count + 1;
N = acc.count;
acc.R_sum = (acc.R_sum * (N - 1) + abs(R)) / N;
R_avg = acc.R_sum;
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 2c — FPS & Height detection (frameratedetector.c)
%% ════════════════════════════════════════════════════════════════════════════

function [fps, H, converged] = frameratedetector_run(R_avg, fs, opts)
% frameratedetector_run  Detect FPS and display height from averaged R[τ].
%
%   [fps, H, converged] = frameratedetector_run(R_avg, fs)
%   [fps, H, converged] = frameratedetector_run(R_avg, fs, opts)
%
%   opts.min_fps    : minimum FPS to search (default 25 Hz)
%   opts.max_fps    : maximum FPS to search (default 200 Hz)
%   opts.min_height : minimum display height in lines (default 400)
%   opts.max_height : maximum display height in lines (default 2000)
%   opts.convergence: consecutive matching detections required (default 3)
%
%   Tau ranges (frameratedetector.c):
%       FRAME range : τ ∈ [fs/MAX_FPS,  fs/MIN_FPS]
%       LINE  range : τ ∈ [fs/(MAX_HEIGHT·MAX_FPS), fs/(MIN_HEIGHT·MIN_FPS)]

if nargin < 3, opts = struct(); end
min_fps    = getf(opts, 'min_fps',    25);
max_fps    = getf(opts, 'max_fps',   200);
min_H      = getf(opts, 'min_height', 400);
max_H      = getf(opts, 'max_height', 2000);
convergence= getf(opts, 'convergence', 3);

fps = NaN;  H = NaN;  converged = false;

N = length(R_avg);

%% ── FRAME peak search ────────────────────────────────────────────────────
tau_min_f = max(1, floor(fs / max_fps));
tau_max_f = min(N, ceil(fs / min_fps));

if tau_max_f <= tau_min_f, return; end

R_frame = R_avg(tau_min_f:tau_max_f);
[~, idx] = max(R_frame);
tau_frame = tau_min_f + idx - 1;       % absolute lag

fps_candidate = fs / tau_frame;

%% ── LINE peak search ─────────────────────────────────────────────────────
tau_min_l = max(1, floor(fs / (max_H * max_fps)));
tau_max_l = min(N, ceil(fs / (min_H * min_fps)));

if tau_max_l <= tau_min_l, return; end

R_line = R_avg(tau_min_l:tau_max_l);
[~, idx] = max(R_line);
tau_line = tau_min_l + idx - 1;

H_candidate = tau_frame / tau_line;

%% ── Convergence (mirrors 3× hash-map check in Main.java:1377) ───────────
%   Single-shot version: caller accumulates and checks convergence counter.
if H_candidate >= min_H && H_candidate <= max_H
    fps = fps_candidate;
    H   = H_candidate;
    converged = true;
end
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 3a — Vertical/horizontal projections (dsp.c : dsp_average_v_h)
%% ════════════════════════════════════════════════════════════════════════════

function [proj_h, proj_v] = dsp_average_v_h(frame, W, H)
% dsp_average_v_h  Column-sum and row-sum projections for blanking detection.
%
%   [proj_h, proj_v] = dsp_average_v_h(frame, W, H)
%
%   frame  : 1-D vector of W×H samples (row-major) OR [H×W] matrix
%   proj_h : [1×W] column sums  → horizontal blanking position
%   proj_v : [H×1] row    sums  → vertical   blanking position
%
%   dsp.c:
%       widthcollapsebuffer[i % W]  += val;   // column sum
%       heightcollapsebuffer[i / W] += val;   // row sum

if isvector(frame)
    img = reshape(double(frame), W, H)';   % → [H × W]
else
    img = double(frame);
    [H, W] = size(img);
end

proj_h = sum(img, 1);    % [1 × W]  column sums
proj_v = sum(img, 2);    % [H × 1]  row sums
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 3b — Blanking boundary detection (syncdetector.c : findbestfit)
%% ════════════════════════════════════════════════════════════════════════════

function [best_id, best_cost] = findbestfit(proj, strip_size)
% findbestfit  Sliding-window search for the blanking (dark) strip position.
%
%   [best_id, best_cost] = findbestfit(proj, strip_size)
%
%   proj       : 1-D projection vector (sum along rows or columns)
%   strip_size : expected blanking width in pixels
%
%   Cost function (syncdetector.c):
%       J(i) = [ (ΣS_out / N_out) − (ΣS_in / N_in) ]²
%
%   The blanking region is darker than active pixels, so J is maximised
%   where "inside" (dark strip) and "outside" (bright active) differ most.

proj = double(proj(:))';
N    = length(proj);
S    = strip_size;

if S >= N
    best_id   = 0;
    best_cost = 0;
    return
end

total_sum = sum(proj);
N_in  = S;
N_out = N - S;

best_cost = -Inf;
best_id   = 0;

% Sliding window via cumulative sum
cs = [0, cumsum(proj)];

for i = 1:N
    i2 = mod(i + S - 1, N) + 1;   % wrap-around end index

    if i2 > i
        sum_in = cs(i2) - cs(i-1+1) + cs(1);   % contiguous
        % simpler: sliding sum without wrap
        sum_in = sum(proj(i:i+S-1));
        if i + S - 1 > N, break; end
    else
        sum_in = sum(proj(i:N)) + sum(proj(1:i2));
    end

    sum_out = total_sum - sum_in;

    mean_in  = sum_in  / N_in;
    mean_out = sum_out / N_out;

    cost = (mean_out - mean_in)^2;

    if cost > best_cost
        best_cost = cost;
        best_id   = i - 1;   % 0-based, matches C
    end
end
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 3c — 2-D circular shift for frame alignment (syncdetector.c)
%% ════════════════════════════════════════════════════════════════════════════

function img_aligned = syncdetector_run(img, dx, dy)
% syncdetector_run  Align frame by circular-shifting (dx, dy) pixels.
%
%   img_aligned = syncdetector_run(img, dx, dy)
%
%   img : [H × W] greyscale image
%   dx  : horizontal shift (columns)  from findbestfit on proj_h
%   dy  : vertical   shift (rows)     from findbestfit on proj_v
%
%   syncdetector.c performs a 2D wrap-around memcpy equivalent to circshift.

img_aligned = circshift(img, [-dy, -dx]);
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 3d — PLL fps fine-tuning (syncdetector.c : frameratepll)
%% ════════════════════════════════════════════════════════════════════════════

function [fps_new, pll] = frameratepll(pll, dx, fps)
% frameratepll  Phase-locked loop that fine-tunes fps from blanking drift.
%
%   [fps_new, pll] = frameratepll(pll, dx, fps)
%
%   pll : PLL state struct (pass [] for first call)
%         fields: avg_speed, locked
%   dx  : current horizontal blanking position (from findbestfit)
%   fps : current frame rate estimate
%
%   syncdetector.c:
%       avg_speed = 0.99·avg_speed + 0.01·vx
%       fps -= avg_speed · SPEED_LO      (locked:   1e-6)
%       fps -= avg_speed · SPEED_HI      (unlocked: 1e-5)

SPEED_LO = 1e-6;   % PLL gain when locked
SPEED_HI = 1e-5;   % PLL gain when unlocking

if isempty(pll)
    pll.avg_speed = 0;
    pll.prev_dx   = dx;
    pll.locked    = false;
end

% Velocity of blanking boundary = change in dx
vx = dx - pll.prev_dx;
pll.prev_dx = dx;

% EMA speed estimate
pll.avg_speed = 0.99 * pll.avg_speed + 0.01 * vx;

% Lock detection: speed near zero
pll.locked = abs(pll.avg_speed) < 0.5;

% PLL correction
alpha = SPEED_LO * pll.locked + SPEED_HI * ~pll.locked;
fps_new = fps - pll.avg_speed * alpha;
end


%% ════════════════════════════════════════════════════════════════════════════
%  Stage 4 — Temporal low-pass / Motion Blur (dsp.c : dsp_timelowpass_run)
%% ════════════════════════════════════════════════════════════════════════════

function img_out = dsp_timelowpass_run(img_raw, img_prev, alpha)
% dsp_timelowpass_run  Exponential moving average across frames (SNR boost).
%
%   img_out = dsp_timelowpass_run(img_raw, img_prev, alpha)
%
%   img_raw  : current frame  [H × W]
%   img_prev : previous output frame (same size), or [] for first frame
%   alpha    : EMA coefficient ∈ (0,1]
%              α → 0 : heavy averaging (slow, cleaner)
%              α → 1 : no averaging   (real-time)
%
%   dsp.c:
%       I[t] = α·I[t−1] + (1−α)·I_raw[t]
%   Note: dsp.c uses (α, 1-α) order (weight on *previous*); here we follow
%         the same convention as the Java slider: α = slider/100 weights new.

if isempty(img_prev) || alpha >= 1.0
    img_out = img_raw;
    return
end

img_out = alpha .* img_raw + (1 - alpha) .* img_prev;
end


%% ════════════════════════════════════════════════════════════════════════════
%  Full pipeline wrapper
%% ════════════════════════════════════════════════════════════════════════════

function [img_out, state] = tsdr_pipeline(x, state, opts)
% tsdr_pipeline  Run the complete TempestSDR C-library DSP pipeline.
%
%   [img_out, state] = tsdr_pipeline(x, state)
%   [img_out, state] = tsdr_pipeline(x, state, opts)
%
%   x     : raw SDR samples for one (approximate) frame
%   state : pipeline state struct (pass [] for first call)
%   opts  : optional parameter struct
%           .fps          initial fps estimate (default 25)
%           .height       initial height estimate (default 625)
%           .out_width    output image width (default 576)
%           .mblur_alpha  motion blur α ∈ (0,1] (default 0.5)
%           .strip_frac   blanking strip as fraction of dim (default 0.05)
%           .lowpass_first apply EMA before sync (default false)
%
%   Pipeline order (dsp.c : dsp_post_process):
%     autogain → autocorrelation → fps/height → [lowpass →] v/h projection
%     → findbestfit → syncdetector → PLL → [→ lowpass] → output

if nargin < 3, opts = struct(); end

fps0       = getf(opts, 'fps',         25);
H0         = getf(opts, 'height',     625);
out_width  = getf(opts, 'out_width',  576);
alpha      = getf(opts, 'mblur_alpha', 0.5);
strip_frac = getf(opts, 'strip_frac', 0.05);
lp_first   = getf(opts, 'lowpass_first', false);
fs         = getf(opts, 'fs',        2.4e6);

%% Initialise state
if isempty(state)
    state.ag   = [];          % autogain
    state.acc  = [];          % autocorrelation accumulator
    state.pll  = [];          % PLL
    state.prev = [];          % previous frame (motion blur)
    state.fps  = fps0;
    state.H    = H0;
    state.conv_count = 0;
    state.conv_key   = '';
end

%% 1. Auto-gain
[x_norm, state.ag] = dsp_autogain_run(x, state.ag);

%% 2. FFT autocorrelation + cumulative average
R             = fft_autocorrelation(x_norm);
[R_avg, state.acc] = accummulate(R, state.acc);

%% 2b. FPS & height detection (with 3× convergence)
[fps_cand, H_cand, ok] = frameratedetector_run(R_avg, fs);
if ok
    key = sprintf('%.1f_%.0f', fps_cand, round(H_cand));
    if strcmp(key, state.conv_key)
        state.conv_count = state.conv_count + 1;
    else
        state.conv_key   = key;
        state.conv_count = 1;
    end
    if state.conv_count >= 3   % AUTO_FRAMERATE_CONVERGANCE_ITERATIONS
        state.fps = fps_cand;
        state.H   = H_cand;
    end
end

fps = state.fps;
H   = round(state.H);

%% 3. Reshape 1-D → 2-D
N_frame = round(fs / fps);
W       = floor(N_frame / H);
needed  = H * W;
if numel(x_norm) < needed
    x_norm(end+1:needed) = 0;
end
img_raw = reshape(x_norm(1:needed), W, H)';   % [H × W]
img_raw = mat2gray(img_raw);

%% 4a. Optional lowpass BEFORE sync (dsp.c mode A)
if lp_first
    img_raw = dsp_timelowpass_run(img_raw, state.prev, alpha);
end

%% 4b. Projections + blanking detection + sync
[proj_h, proj_v] = dsp_average_v_h(img_raw, W, H);

dx = findbestfit(proj_h, max(1, round(W * strip_frac)));
dy = findbestfit(proj_v, max(1, round(H * strip_frac)));

img_synced = syncdetector_run(img_raw, dx, dy);

%% 4c. PLL fps fine-tuning
[fps_pll, state.pll] = frameratepll(state.pll, dx, fps);
state.fps = fps_pll;

%% 4d. Optional lowpass AFTER sync (dsp.c mode B — default)
if ~lp_first
    img_synced = dsp_timelowpass_run(img_synced, state.prev, alpha);
end
state.prev = img_synced;

%% 5. Bilinear resize to output width
img_out = imresize(img_synced, [H, out_width], 'bilinear');
end


%% ── Utility ──────────────────────────────────────────────────────────────────
function v = getf(s, f, d)
if isfield(s, f), v = s.(f); else, v = d; end
end
