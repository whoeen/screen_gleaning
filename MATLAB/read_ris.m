%% read_ris.m
% NI USRP2940R + LabVIEW로 저장한 .ris IQ 파일 읽기.
%
% 포맷: 16-bit signed integer, big-endian, 인터리브 [I Q I Q ...]
%       complex = I - j*Q
%
% Usage:
%   signal = read_ris(filepath)
%
% Input:
%   filepath : .ris 파일 경로
%
% Output:
%   signal : 복소 IQ 신호 [1 × N complex double]

function signal = read_ris(filepath)

fid = fopen(filepath, 'r');
if fid == -1
    error('read_ris: 파일을 열 수 없습니다: %s', filepath);
end

raw = fread(fid, Inf, 'integer*2', 0, 'ieee-be');
fclose(fid);

if numel(raw) < 2
    error('read_ris: 파일이 비어 있거나 너무 작습니다.');
end

if mod(numel(raw), 2) ~= 0
    raw = raw(1:end-1);
end

iq = reshape(raw, 2, []);
signal = double(iq(1,:)) - 1j * double(iq(2,:));

end
