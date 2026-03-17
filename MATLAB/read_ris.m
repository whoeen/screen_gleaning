%% read_ris.m
% Read NI USRP (LabVIEW) .ris IQ signal file.
%
% NI USRP2940R로 수집한 .ris 파일 포맷:
%   - 16-bit signed integer, big-endian (ieee-be)
%   - 인터리브: [I0 Q0 I1 Q1 ...]  →  reshape(2, N)
%   - complex = I - j*Q
%
% Usage:
%   [signal, fs, fc] = read_ris(filepath)
%   [signal, fs, fc] = read_ris(filepath, fs, fc)
%
% Inputs:
%   filepath : 파일 경로 (.ris)
%   fs       : 샘플레이트 [Hz]  (생략 시 사용자에게 입력 받음)
%   fc       : 반송 주파수 [Hz] (생략 시 사용자에게 입력 받음)
%
% Outputs:
%   signal   : 복소 IQ 신호  [1 × N complex double]
%   fs       : 샘플레이트 [Hz]
%   fc       : 반송 주파수 [Hz]

function [signal, fs, fc] = read_ris(filepath, fs, fc)

%% ── 파라미터 입력 ────────────────────────────────────────────────────────────
if nargin < 2 || isempty(fs)
    fs = input('[read_ris] Sample rate (Hz) [e.g. 2.4e6]: ');
end
if nargin < 3 || isempty(fc)
    fc = input('[read_ris] Carrier frequency (Hz) [e.g. 400e6]: ');
end

%% ── 파일 열기 ────────────────────────────────────────────────────────────────
fid = fopen(filepath, 'r');
if fid == -1
    error('read_ris: 파일을 열 수 없습니다: %s', filepath);
end

%% ── IQ 읽기 (16-bit int, big-endian) ────────────────────────────────────────
raw = fread(fid, Inf, 'integer*2', 0, 'ieee-be');
fclose(fid);

if numel(raw) < 2
    error('read_ris: 파일이 비어 있거나 너무 작습니다.');
end

% 짝수 샘플 수 맞추기
if mod(numel(raw), 2) ~= 0
    raw = raw(1:end-1);
end

%% ── I/Q 분리 ─────────────────────────────────────────────────────────────────
iq = reshape(raw, 2, []);   % 행 1 = I, 행 2 = Q
signal = double(iq(1,:)) - 1j * double(iq(2,:));

fprintf('[read_ris] 로드 완료: %d 샘플  fs=%.3g Hz  fc=%.3g Hz\n', ...
        numel(signal), fs, fc);
end
