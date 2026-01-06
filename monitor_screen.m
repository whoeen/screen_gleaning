function monitor_screen(Htotal, Vtotal, env_bits, i, j, fc, outdir)
    if nargin < 7, outdir = "meeting_results_1015"; end
    if ~exist(outdir, 'dir'), mkdir(outdir); end

    img = reshape(env_bits, [Htotal, Vtotal]).';
    img = img - min(img(:));
    if max(img(:))>0, img = img./max(img(:)); end

    filename = fullfile(outdir, sprintf('reconstructed_T%d_fc%d.png', j, i));
    imwrite(im2uint8(img), filename);
end
