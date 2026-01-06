h = waterfall (fnc(1:subsamp:end)*fs/fsFac + fcarrier/fsFac,anc*fs/asFac,((abs(ync(:, 1:subsamp:end)))), zeros(size(ync(:, 1:subsamp:end))));
set (h, 'edgecolor', [0 0 0]);
set (h, 'facecolor', [0.9 0.9 0.95]);
grid on;
axis tight;
xlabel ('f (Hz)');
ylabel ('\alpha (Hz)');