%% run_emage.m
% NI USRP2940R .ris 파일 → EMAGE 복원 스크립트
%
% 실행 전 확인:
%   - tsdr_dsp.m, tsdr_core.m 이 같은 폴더에 있을 것
%   - 아래 ris_file 경로를 자신의 파일로 수정할 것
%
% 사용법:
%   MATLAB 커맨드창에서: run_emage

clear; clc;

%% ── 설정 ─────────────────────────────────────────────────────────────────────

ris_file = 'iphone6_비밀번호화면_LCD커넥터부분_2026년03월13일11시59분08.54초.ris';

fs  = 25e6;    % 샘플레이트 [Hz]  (25 MSa/s)
fLO = 105e6;   % 다운컨버전 LO [Hz] (표시용)

% iPhone 6: 750×1334 @ 60 fps
fps_init    = 60;
height_init = 1334;
out_width   = 750;

n_frames    = 50;    % 처리할 프레임 수 (많을수록 SNR↑, 시간↑)
mblur_alpha = 0.3;   % 시간 평균 강도: 0=강한 평균, 1=평균 없음

%% ── .ris 파일 읽기 ───────────────────────────────────────────────────────────
fprintf('▶ .ris 읽는 중: %s\n', ris_file);

fid = fopen(ris_file, 'r');
if fid == -1
    error('파일을 열 수 없습니다. 경로를 확인하세요:\n  %s', ris_file);
end
raw = fread(fid, Inf, 'integer*2', 0, 'ieee-be');
fclose(fid);

if mod(numel(raw), 2), raw = raw(1:end-1); end

iq  = reshape(raw, 2, []);
sig = double(iq(1,:)) - 1j * double(iq(2,:));   % I - jQ
x   = abs(sig);                                  % 포락선 (실수 신호)

fprintf('   샘플 수 : %d\n', numel(x));
fprintf('   녹음 길이: %.2f 초\n', numel(x)/fs);

%% ── 프레임 단위 처리 (tsdr_pipeline) ────────────────────────────────────────
N_frame = round(fs / fps_init);
n_avail = floor(numel(x) / N_frame);
n_proc  = min(n_frames, n_avail);

fprintf('\n▶ 프레임 처리: %d / %d 프레임\n', n_proc, n_avail);
fprintf('   fps=%.0f  height=%.0f  out_width=%d  mblur=%.2f\n\n', ...
        fps_init, height_init, out_width, mblur_alpha);

opts.fs          = fs;
opts.fps         = fps_init;
opts.height      = height_init;
opts.out_width   = out_width;
opts.mblur_alpha = mblur_alpha;
opts.strip_frac  = 0.05;

state   = [];
img_out = [];

for k = 1:n_proc
    seg = x((k-1)*N_frame + 1 : k*N_frame);
    [img_out, state] = tsdr_pipeline(seg, state, opts);

    if mod(k, 10) == 0 || k == 1
        fprintf('  프레임 %3d/%d  fps=%.2f  H=%d\n', ...
                k, n_proc, state.fps, round(state.H));
    end
end

%% ── 저장 및 표시 ─────────────────────────────────────────────────────────────
img_save = mat2gray(img_out);

[folder, ~, ~] = fileparts(ris_file);
if isempty(folder), folder = pwd; end
out_path = fullfile(folder, 'emage_result.png');

imwrite(img_save, out_path);
fprintf('\n▶ 저장 완료: %s\n', out_path);

figure('Name', 'EMAGE 복원 결과', 'NumberTitle', 'off');
imshow(img_save, []);
title(sprintf('iPhone6 EMAGE  |  fps=%.1f  H=%d  frames=%d  fs=%.0fMSa/s  fLO=%.0fMHz', ...
              state.fps, round(state.H), n_proc, fs/1e6, fLO/1e6));
