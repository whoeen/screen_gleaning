%% lenet_emage_iph6.m
% LeNet_EMAGE network for iPhone 6 / iPhone 6S single-digit classification.
% MATLAB port of LeNet_EMAGE_iph6 in Recognition/utils.py (lines 51-69).
%
% Input  : [31 × 20 × 1]  greyscale digit patch  (height × width × channels)
% Output : 10-class logit vector  (digits 0-9)
%
% Architecture (matching PyTorch forward pass):
%   conv1  : 1→6  ch, 5×5, valid  → [27×16×6]
%   relu + maxpool 2×2             → [13×8×6]
%   conv2  : 6→16 ch, 5×5, valid  → [9×4×16]
%   relu + maxpool 2×2             → [4×2×16] = 128 features
%   fc1    : 128→120
%   fc2    : 120→84
%   fc3    : 84→10
%
% Requires: Deep Learning Toolbox

function lgraph = lenet_emage_iph6()
% lenet_emage_iph6  Return a layerGraph for the iPhone-6 LeNet_EMAGE model.

layers = [
    imageInputLayer([31 20 1], 'Normalization', 'none', 'Name', 'input')

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
