%% lenet_emage_honor.m
% LeNet_EMAGE network for Honor 6X single-digit classification.
% MATLAB port of LeNet_EMAGE_honor in Recognition/utils.py (lines 71-89).
%
% Input  : [45 × 21 × 1]  greyscale digit patch  (height × width × channels)
% Output : 10-class logit vector  (digits 0-9)
%
% Architecture:
%   conv1  : 1→6  ch, 5×5, valid  → [41×17×6]
%   relu + maxpool 2×2             → [20×8×6]
%   conv2  : 6→16 ch, 5×5, valid  → [16×4×16]
%   relu + maxpool 2×2             → [8×2×16] = 256 features
%   fc1    : 256→120
%   fc2    : 120→84
%   fc3    : 84→10
%
% Note: fc1 input is 256 (vs 128 for iPhone 6) due to the larger 45-px height.
%
% Requires: Deep Learning Toolbox

function lgraph = lenet_emage_honor()
% lenet_emage_honor  Return a layerGraph for the Honor-6X LeNet_EMAGE model.

layers = [
    imageInputLayer([45 21 1], 'Normalization', 'none', 'Name', 'input')

    convolution2dLayer(5, 6,  'Padding', 'valid', 'Name', 'conv1')
    reluLayer('Name', 'relu1')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool1')

    convolution2dLayer(5, 16, 'Padding', 'valid', 'Name', 'conv2')
    reluLayer('Name', 'relu2')
    maxPooling2dLayer(2, 'Stride', 2, 'Name', 'pool2')

    fullyConnectedLayer(120, 'Name', 'fc1')
    reluLayer('Name', 'relu3')

    fullyConnectedLayer(84,  'Name', 'fc2')
    reluLayer('Name', 'relu4')

    fullyConnectedLayer(10,  'Name', 'fc3')

    softmaxLayer('Name', 'softmax')
    classificationLayer('Name', 'output')
];

lgraph = layerGraph(layers);
end
