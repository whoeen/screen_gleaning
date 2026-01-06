function [env_bits] = digital_down_converter(common_mode_emission,output_bitnum,j,fc,Ts,sps,delta_f)
    
    Tstart = (j/4)*(output_bitnum);
    idx1 = Tstart;
    idx2 = Tstart + output_bitnum - 1;

    common_mode_emission_collect = common_mode_emission(idx1:idx2);

    n = 0 : numel(common_mode_emission_collect)-1;
    t = (Tstart + n) * Ts;
    real_lo = exp(-1j*2*pi*(fc - delta_f) .* t); 

    baseband_bits = abs(lowpass(common_mode_emission_collect.*real_lo,0.2));  
    x= reshape(baseband_bits,sps,[]).';
    env_bits = mean(x,2);

end
