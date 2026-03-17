%% resnet18_eyedoctor.m
% ResNet-18 for eye-doctor letter classification (10 Sloan letters).
% MATLAB port of train_eyedoctor.py (line 26):
%   model = getattr(models, 'resnet18')(num_classes=10, pretrained=False)
%
% Input  : [224 × 224 × 3]  RGB image
% Output : 10-class logit vector
%          Classes: C D E F L N O P T Z  (Sloan chart letters)
%
% Requires: Deep Learning Toolbox

function net = resnet18_eyedoctor()
% resnet18_eyedoctor  Return an untrained ResNet-18 with 10 output classes.
%
%   This mirrors resnet18(num_classes=10, pretrained=False) from PyTorch.
%   MATLAB's resnet18() outputs 1000 classes; we replace the final FC layer.

try
    % Load stock ResNet-18 (requires Deep Learning Toolbox Model for ResNet-18)
    base = resnet18;
catch
    error(['resnet18_eyedoctor: resnet18() not found. ' ...
           'Install the Deep Learning Toolbox Model for ResNet-18 Support Package.']);
end

% Replace final fully-connected layer: 512→1000 becomes 512→10
lgraph = layerGraph(base);
new_fc = fullyConnectedLayer(10, 'Name', 'fc', ...
                              'WeightLearnRateFactor',  10, ...
                              'BiasLearnRateFactor',    10);
new_sm = softmaxLayer('Name', 'softmax');
new_cl = classificationLayer('Name', 'output', ...
                              'Classes', {'C','D','E','F','L','N','O','P','T','Z'});

lgraph = replaceLayer(lgraph, 'fc1000',       new_fc);
lgraph = replaceLayer(lgraph, 'fc1000_softmax', new_sm);
lgraph = replaceLayer(lgraph, 'ClassificationLayer_fc1000', new_cl);

net = lgraph;
end
