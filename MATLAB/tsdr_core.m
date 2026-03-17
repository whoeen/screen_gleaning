%% tsdr_core.m
% Core TempestSDR signal-processing functions converted from Java (Main.java).
%
% Covers:
%   detect_sync()       – autocorrelation-based fps / height detection
%   fps_from_index()    – sample-index  →  fps   (FPSTransformer.fromIndex)
%   fps_to_index()      – fps           →  sample-index
%   height_from_index() – sample-index  →  height (HeightTransformer.fromIndex)
%   height_to_index()   – height        →  sample-index
%   reconstruct_frame() – 1-D EM stream → 2-D greyscale image
%   process_frame()     – gain normalise + motion-blur (EMA)
%   resize_frame()      – bilinear resize  (imresize wrapper)
%
% Dependencies: Signal Processing Toolbox (xcorr, findpeaks)
%               Image Processing Toolbox  (imresize)

%% ── fps helpers (FPSTransformer in Main.java:1413-1446) ─────────────────────

function fps = fps_from_index(id, offset, fs)
% fps_from_index  Convert peak-lag index to frame rate.
%   fps = fps_from_index(id, offset, fs)
%
%   id     : 0-based lag index of autocorrelation FRAME peak
%   offset : spinner offset value from GUI
%   fs     : SDR sample rate [Hz]
fps = fs / (offset + id);
end


function id = fps_to_index(fps_val, offset, fs)
% fps_to_index  Convert frame rate back to peak-lag index.
id = round(fs / fps_val - offset);
end


%% ── height helpers (HeightTransformer in Main.java:1448-1487) ───────────────

function h = height_from_index(id_line, offset_line, id_frame, offset_frame, fs, fps_val)
% height_from_index  Derive display height from LINE autocorrelation peak.
%
%   id_line, offset_line  : lag index / offset for LINE peak
%   id_frame, offset_frame: lag index / offset for FRAME peak  (or [] to use fps)
%   fs                    : sample rate [Hz]
%   fps_val               : frame rate [Hz]  (used when id_frame is [])

if isempty(id_frame)
    N_frame = fs / fps_val;
else
    N_frame = offset_frame + id_frame;
end

N_line = offset_line + id_line;
h = N_frame / N_line;
end


function id = height_to_index(h_val, offset_line, id_frame, offset_frame, fs, fps_val)
% height_to_index  Convert height back to LINE peak index.
if isempty(id_frame)
    N_frame = fs / fps_val;
else
    N_frame = offset_frame + id_frame;
end
id = round(N_frame / h_val - offset_line);
end


%% ── synchronisation detection (onIncommingPlot in Main.java:1350-1395) ──────

function [fps_out, height_out, converged] = detect_sync(signal, fs, opts)
% detect_sync  Detect fps and display height from raw EM signal via xcorr.
%
%   [fps_out, height_out, converged] = detect_sync(signal, fs)
%   [fps_out, height_out, converged] = detect_sync(signal, fs, opts)
%
%   opts.fps_offset    : FPS spinner offset    (default 0)
%   opts.line_offset   : LINE spinner offset   (default 0)
%   opts.convergence   : required consecutive hits to confirm (default 3)
%   opts.min_fps       : minimum plausible fps (default 10)
%   opts.max_fps       : maximum plausible fps (default 200)
%
%   Returns converged=true once the same (fps,height) key is seen
%   opts.convergence times in a row (mirrors AUTO_FRAMERATE_CONVERGANCE_ITERATIONS).

if nargin < 3, opts = struct(); end
fps_offset  = getfield_default(opts, 'fps_offset',  0);
line_offset = getfield_default(opts, 'line_offset', 0);
convergence = getfield_default(opts, 'convergence', 3);   % Java constant = 3
min_fps     = getfield_default(opts, 'min_fps',    10);
max_fps     = getfield_default(opts, 'max_fps',   200);

fps_out    = NaN;
height_out = NaN;
converged  = false;

N = length(signal);

% ── 1. One-sided normalised autocorrelation ───────────────────────────────
R = xcorr(double(signal), 'normalized');
R = R(N:end);           % keep lags 0 … N-1

% ── 2. Find all peaks ─────────────────────────────────────────────────────
[~, locs] = findpeaks(R, 'MinPeakProminence', 0.05, 'SortStr', 'descend');
locs = sort(locs);      % restore ascending lag order

if numel(locs) < 2
    return
end

% ── 3. FRAME peak → fps ───────────────────────────────────────────────────
id_F = locs(1) - 1;     % 0-based lag
fps_candidate = fps_from_index(id_F, fps_offset, fs);

if fps_candidate < min_fps || fps_candidate > max_fps
    return
end

% ── 4. LINE peak → height ─────────────────────────────────────────────────
id_L = locs(2) - 1;
h_candidate = height_from_index(id_L, line_offset, id_F, fps_offset, fs, []);

if h_candidate < 1
    return
end

% ── 5. Convergence check (persistent state via output struct) ─────────────
%   In real-time use, call detect_sync repeatedly and accumulate the counter
%   externally.  Here we return the candidates and set converged=true to
%   signal a valid detection (single-shot version).
fps_out    = fps_candidate;
height_out = h_candidate;
converged  = true;      % caller implements the ×3 convergence loop if needed
end


%% ── 1-D stream → 2-D frame (onFrameReady in Main.java:1195) ─────────────────

function img = reconstruct_frame(signal, fps, height, fs)
% reconstruct_frame  Reshape a 1-D EM sample stream into a 2-D greyscale image.
%
%   img = reconstruct_frame(signal, fps, height, fs)
%
%   signal : 1-D vector of real-valued SDR samples (one frame worth)
%   fps    : detected frame rate [Hz]
%   height : detected display height [lines]
%   fs     : SDR sample rate [Hz]
%
%   Returns img  [height × width] normalised to [0,1].

N_frame = round(fs / fps);
H       = round(height);
W       = floor(N_frame / H);          % samples per line = image width

% Trim / zero-pad to exactly H×W
needed = H * W;
if numel(signal) >= needed
    frame = signal(1:needed);
else
    frame = [signal(:); zeros(needed - numel(signal), 1)];
end

% Reshape: samples fill row-by-row (column-major in MATLAB → transpose trick)
% Java: row = floor(n*H/N_frame), col = n mod W
% Equivalent: reshape as (W, H) then transpose.
img = reshape(double(frame), W, H)';   % → [H × W]
img = mat2gray(img);                   % normalise to [0,1]
end


%% ── Gain & motion-blur (TSDRLibrary native processing) ──────────────────────

function img_out = process_frame(img_raw, img_prev, gain, mblur)
% process_frame  Apply gain normalisation and exponential motion blur.
%
%   img_out = process_frame(img_raw, img_prev, gain, mblur)
%
%   img_raw  : current raw frame [H × W], range [0,1]
%   img_prev : previous processed frame (same size), or [] for first frame
%   gain     : display gain  ∈ [0,1]   (0 = darkest, 1 = full stretch)
%   mblur    : motion-blur α ∈ [0,1]   (0 = max blur, 1 = no blur)
%              α → 0 : heavy temporal averaging (ghost trails)
%              α → 1 : real-time, no averaging
%
%   Motion-blur model (EMA):
%       I_out[t] = (1−α)·I_out[t−1] + α·I_raw[t]

% ── Gain: linear stretch ──────────────────────────────────────────────────
img_gained = img_raw * gain;
img_gained = min(img_gained, 1.0);

% ── Motion blur (EMA) ─────────────────────────────────────────────────────
alpha = mblur;   % α in [0,1]
if isempty(img_prev) || alpha >= 1.0
    img_out = img_gained;
else
    img_out = (1 - alpha) .* img_prev + alpha .* img_gained;
end
end


%% ── Bilinear resize (resize() in Main.java:1181) ────────────────────────────

function img_out = resize_frame(img, out_width)
% resize_frame  Resize a frame to out_width columns, preserving height.
%               Matches Java bilinear interpolation in Main.java:1186.
%
%   img_out = resize_frame(img, out_width)

[H, ~] = size(img);
img_out = imresize(img, [H, out_width], 'bilinear');
end


%% ── Utility ──────────────────────────────────────────────────────────────────

function v = getfield_default(s, field, default)
if isfield(s, field)
    v = s.(field);
else
    v = default;
end
end
