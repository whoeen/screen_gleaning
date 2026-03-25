%% emage_from_ris.m
% NI USRP2940R + LabVIEW로 저장한 .ris 파일에서 EMAGE를 복원합니다.
%
% 사용법:
%   emage_from_ris                        % 모든 파라미터 대화형 입력
%   emage_from_ris('test1.ris', 2.4e6)    % 파일·샘플레이트 지정
%   emage_from_ris('test1.ris', 2.4e6, 'fps', 60, 'height', 768)  % 동기화 수동 지정
%
% 필수:
%   read_ris.m, tsdr_core.m, tsdr_dsp.m, emage_preprocess.m

function emage_from_ris(filepath, fs, varargin)

%% ── 입력 파라미터 ────────────────────────────────────────────────────────────
if nargin < 1 || isempty(filepath)
    filepath = input('[emage] .ris 파일 경로: ', 's');
end
if nargin < 2 || isempty(fs)
    fs = input('[emage] Sample rate (Hz) [예: 2.4e6]: ');
end

% 선택적 파라미터 파싱
p = inputParser;
addParameter(p, 'fc',     [],   @isnumeric);   % 반송 주파수 (표시용)
addParameter(p, 'fps',    [],   @isnumeric);   % 수동 fps (자동 감지 안 될 때)
addParameter(p, 'height', [],   @isnumeric);   % 수동 height
addParameter(p, 'gain',   0.8,  @isnumeric);
addParameter(p, 'mblur',  0.6,  @isnumeric);
addParameter(p, 'out_w',  0,    @isnumeric);   % 0 = 원본 너비 유지
addParameter(p, 'outdir', '',   @ischar);
parse(p, varargin{:});
opt = p.Results;

%% ── 1. .ris 파일 읽기 ────────────────────────────────────────────────────────
fprintf('\n[1/4] .ris 파일 읽는 중...\n');

fid = fopen(filepath, 'r');
if fid == -1
    error('파일을 열 수 없습니다: %s', filepath);
end
raw = fread(fid, Inf, 'integer*2', 0, 'ieee-be');
fclose(fid);

if mod(numel(raw), 2) ~= 0
    raw = raw(1:end-1);
end

iq = reshape(raw, 2, []);
signal_iq = double(iq(1,:)) - 1j * double(iq(2,:));

fprintf('    샘플 수: %d  (%.2f 초 @ fs=%.3g Hz)\n', ...
        numel(signal_iq), numel(signal_iq)/fs, fs);

%% ── 2. 포락선 검출 + 전처리 ─────────────────────────────────────────────────
fprintf('[2/4] 전처리 중...\n');

x = abs(signal_iq);          % 포락선(envelope) → 실수 신호
x_lp = lowpass_ma(x, 5);    % 동기 감지 전 저역통과 필터

%% ── 3. 동기화 감지 (fps, height) ────────────────────────────────────────────
fprintf('[3/4] 동기화 감지 중...\n');

if ~isempty(opt.fps) && ~isempty(opt.height)
    % 수동 지정
    fps_det = opt.fps;
    H_det   = opt.height;
    fprintf('    수동 설정: fps=%.2f  height=%.0f\n', fps_det, H_det);
else
    [fps_det, H_det, ok] = detect_sync(x_lp, fs);

    if ok
        fprintf('    자동 감지: fps=%.2f  height=%.1f\n', fps_det, H_det);
    else
        fprintf('    자동 감지 실패.\n');
        fps_det = input('    fps 직접 입력 [예: 60]: ');
        H_det   = input('    height (lines) 직접 입력 [예: 768]: ');
    end
end

%% ── 4. 프레임 복원 ───────────────────────────────────────────────────────────
fprintf('[4/4] 프레임 복원 중...\n');

N_frame   = round(fs / fps_det);
n_frames  = floor(numel(x) / N_frame);

if n_frames < 1
    error('신호가 한 프레임보다 짧습니다. fs/fps를 확인하세요.');
end

fprintf('    가용 프레임 수: %d\n', n_frames);

% 모든 프레임을 평균하면 노이즈가 줄어듬
img_acc = [];
for k = 1:n_frames
    seg = x((k-1)*N_frame + 1 : k*N_frame);
    img_raw = reconstruct_frame(seg, fps_det, H_det, fs);

    if isempty(img_acc)
        img_acc = double(img_raw);
    else
        % 지수 이동 평균 (EMA, mblur 적용)
        img_acc = process_frame(img_raw, img_acc, opt.gain, opt.mblur);
    end
end

img_final = mat2gray(img_acc);   % [0,1]로 정규화

% 출력 너비 리사이즈 (지정 시)
if opt.out_w > 0
    img_final = resize_frame(img_final, opt.out_w);
end

%% ── 저장 ─────────────────────────────────────────────────────────────────────
if isempty(opt.outdir)
    out_dir = fullfile(fileparts(mfilename('fullpath')), 'out');
else
    out_dir = opt.outdir;
end
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

[~, name] = fileparts(filepath);
fname = fullfile(out_dir, [name '_emage.png']);
imwrite(img_final, fname);
fprintf('\n저장 완료: %s\n', fname);

%% ── 표시 ─────────────────────────────────────────────────────────────────────
figure('Name', 'EMAGE 복원 결과');
imshow(img_final, []);
title(sprintf('%s  |  fps=%.1f  H=%d  frames=%d', name, fps_det, round(H_det), n_frames));

end
