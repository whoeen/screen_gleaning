%% emage_flowchart.m
% Draws the complete emage capture & restoration pipeline as a MATLAB figure.
%
% Pipeline:
%   [Analysis] → [Automation/Capture] → [Recognition]
%
% Run this script to display the flowchart.

function emage_flowchart()

fig = figure('Name', 'EMAGE Capture & Restoration Pipeline', ...
             'Color', 'w', 'Position', [50 50 1100 820]);
ax = axes('Position', [0 0 1 1], 'Visible', 'off');
axis([0 1 0 1]); hold on;

%% ── Helper closures ─────────────────────────────────────────────────────────
box_  = @(x,y,w,h,clr,txt) draw_box(ax, x, y, w, h, clr, txt);
arr_  = @(x1,y1,x2,y2)     draw_arrow(ax, x1, y1, x2, y2);
note_ = @(x,y,txt)          text(x, y, txt, 'FontSize', 7.5, ...
                                  'Color', [0.3 0.3 0.3], ...
                                  'HorizontalAlignment', 'center', ...
                                  'Parent', ax);

%% ── Column X positions ───────────────────────────────────────────────────────
xA = 0.08;   % Analysis column
xB = 0.38;   % Automation / SDR column
xC = 0.68;   % Recognition column

bw = 0.22;   % box width
bh = 0.055;  % box height

%% ══════════════════════════════════════════════════════════════════════════════
%  COLUMN A  –  Analysis (image generation)
%% ══════════════════════════════════════════════════════════════════════════════
text(xA + bw/2, 0.97, 'ANALYSIS', 'FontWeight', 'bold', 'FontSize', 10, ...
     'HorizontalAlignment', 'center', 'Color', [0.1 0.4 0.1], 'Parent', ax);

yA = [0.88 0.79 0.70 0.61 0.52];

box_(xA, yA(1), bw, bh, [0.85 1.0 0.85], {'XeLaTeX render', '(Sloan/SMS/Grid)'});
box_(xA, yA(2), bw, bh, [0.85 1.0 0.85], {'PDF → ImageMagick', '→ JPG  (326 DPI)'});
box_(xA, yA(3), bw, bh, [0.85 1.0 0.85], {'Grayscale + resize', '(iPhone 6: 375×667 pt)'});
box_(xA, yA(4), bw, bh, [0.85 1.0 0.85], {'Save to', 'grayfont_letters_XX/'});
box_(xA, yA(5), bw, bh, [0.72 0.93 0.72], {'Ground-truth TXT', '(grid digits)'});

for k = 1:length(yA)-1
    arr_(xA+bw/2, yA(k),   xA+bw/2, yA(k+1)+bh);
end

note_(xA+bw/2, yA(5)-0.04, '110 letter imgs  |  N×6-digit SMS  |  10 grids');

%% ══════════════════════════════════════════════════════════════════════════════
%  COLUMN B  –  Automation / SDR capture
%% ══════════════════════════════════════════════════════════════════════════════
text(xB + bw/2, 0.97, 'AUTOMATION / SDR', 'FontWeight', 'bold', 'FontSize', 10, ...
     'HorizontalAlignment', 'center', 'Color', [0.1 0.1 0.5], 'Parent', ax);

yB = [0.88 0.79 0.70 0.61 0.52 0.43 0.34 0.25 0.16 0.07];

box_(xB, yB(1),  bw, bh, [0.85 0.85 1.0],  {'WebSocket server', '(port 8081)'});
box_(xB, yB(2),  bw, bh, [0.85 0.85 1.0],  {'DUT phone displays', 'image (index.html)'});
box_(xB, yB(3),  bw, bh, [0.85 0.85 1.0],  {'SDR receives EM', 'emission  x[n]'});
box_(xB, yB(4),  bw, bh, [0.85 0.85 1.0],  {'Autocorrelation', 'R[τ] = xcorr(x,x)'});
box_(xB, yB(5),  bw, bh, [0.75 0.75 1.0],  {'FRAME peak → fps', 'τ* = fs/fps'});
box_(xB, yB(6),  bw, bh, [0.75 0.75 1.0],  {'LINE peak → height', 'H = N_frame/N_line'});
box_(xB, yB(7),  bw, bh, [0.85 0.85 1.0],  {'1D → 2D reshape', 'reshape(x, W, H)'''});
box_(xB, yB(8),  bw, bh, [0.85 0.85 1.0],  {'Gain normalize +', 'Motion blur (EMA)'});
box_(xB, yB(9),  bw, bh, [0.85 0.85 1.0],  {'Bilinear resize', '→ image_width px'});
box_(xB, yB(10), bw, bh, [0.65 0.75 1.0],  {'Save PNG', 'out/<name><idx>.png'});

for k = 1:length(yB)-1
    arr_(xB+bw/2, yB(k), xB+bw/2, yB(k+1)+bh);
end

note_(xB+bw/2, yB(5)+bh+0.01, 'convergence ×3');
note_(xB+bw/2, yB(6)+bh+0.01, 'convergence ×3');

%% ── Horizontal arrow: Analysis → Automation ─────────────────────────────────
arr_(xA+bw, yB(2)+bh/2, xB, yB(2)+bh/2);
note_((xA+bw+xB)/2, yB(2)+bh/2+0.025, 'JPG images');

%% ══════════════════════════════════════════════════════════════════════════════
%  COLUMN C  –  Recognition (CNN)
%% ══════════════════════════════════════════════════════════════════════════════
text(xC + bw/2, 0.97, 'RECOGNITION (CNN)', 'FontWeight', 'bold', 'FontSize', 10, ...
     'HorizontalAlignment', 'center', 'Color', [0.5 0.1 0.1], 'Parent', ax);

yC = [0.88 0.79 0.70 0.61 0.52 0.43 0.34 0.25 0.16];

box_(xC, yC(1), bw, bh, [1.0 0.85 0.85], {'Load emage PNG', 'dataset'});
box_(xC, yC(2), bw, bh, [1.0 0.85 0.85], {'Normalize', 'I = (I−μ)/σ'});
box_(xC, yC(3), bw, bh, [1.0 0.85 0.85], {'Crop 6 digit patches', '20×31 px (iph6)'});
box_(xC, yC(4), bw, bh, [1.0 0.75 0.75], {'LeNet_EMAGE', 'conv5→pool→conv5→pool→FC'});
box_(xC, yC(5), bw, bh, [1.0 0.85 0.85], {'Softmax → argmax', '(0–9 digit class)'});
box_(xC, yC(6), bw, bh, [1.0 0.85 0.85], {'Compare to GT', 'digit accuracy'});
box_(xC, yC(7), bw, bh, [1.0 0.85 0.85], {'Save checkpoint', 'if val_acc improved'});
box_(xC, yC(8), bw, bh, [0.9  0.7  0.7],  {'Test: cross-device', 'cross-session eval'});
box_(xC, yC(9), bw, bh, [0.9  0.7  0.7],  {'Report accuracy', '(digit / code level)'});

for k = 1:length(yC)-1
    arr_(xC+bw/2, yC(k), xC+bw/2, yC(k+1)+bh);
end

%% ── Horizontal arrow: Automation → Recognition ───────────────────────────────
arr_(xB+bw, yC(1)+bh/2, xC, yC(1)+bh/2);
note_((xB+bw+xC)/2, yC(1)+bh/2+0.025, 'out/*.png');

%% ── Title ────────────────────────────────────────────────────────────────────
text(0.5, 0.995, 'EMAGE Capture & Restoration Pipeline', ...
     'FontSize', 13, 'FontWeight', 'bold', ...
     'HorizontalAlignment', 'center', 'Parent', ax);

hold off;

end  % emage_flowchart


%% ── Local drawing helpers ────────────────────────────────────────────────────

function draw_box(ax, x, y, w, h, clr, lines)
% Draw a filled rounded rectangle with centred multi-line text.
rectangle('Position', [x y w h], ...
          'Curvature', 0.2, ...
          'FaceColor', clr, ...
          'EdgeColor', [0.3 0.3 0.3], ...
          'LineWidth', 1.2, ...
          'Parent', ax);
if ischar(lines), lines = {lines}; end
txt = strjoin(lines, newline);
text(x+w/2, y+h/2, txt, ...
     'HorizontalAlignment', 'center', ...
     'VerticalAlignment',   'middle', ...
     'FontSize', 8, ...
     'Parent', ax);
end


function draw_arrow(ax, x1, y1, x2, y2)
% Draw a downward (or rightward) arrow between two points.
annotation('arrow', ...
    [x1, x2], ...
    [y1, y2], ...
    'HeadLength', 6, ...
    'HeadWidth',  5, ...
    'Color', [0.2 0.2 0.2]);
end
