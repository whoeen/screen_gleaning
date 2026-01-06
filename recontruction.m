Hact = 1920; Hfp = 88; Hsync = 44; Hbp = 148; Htotal = 2200;
Vact = 1080; Vfp = 4;  Vsync = 5;  Vbp = 36;  Vtotal = 1125;
fref = 60;
fH = fref * Vtotal;
frame_pixel_num = Htotal*Vtotal;

bit_per_pixel = 10;
epsilon = 0.01;
sps = bit_per_pixel/epsilon;
output_bitnum = frame_pixel_num*sps;

fp = fref * frame_pixel_num;
fb = fp * bit_per_pixel;


Tp = 1/fp;
Tb = 1/fb;
Ts = 1/(fb * sps);
Tdelay = Tb*epsilon;

number_fc = 40;
number_frame = 3;


m = imread('TEMPEST_test_image_1.png');
B = to_limited(m(:,:,3)); G = to_limited(m(:,:,2)); R = to_limited(m(:,:,1));
B = reshape(B.', 1, []); G = reshape(G.', 1, []); R = reshape(R.', 1, []);  
video = [B; G; R]; 

bits = hdmi_1080_frame(video,number_frame);
common_mode_emission = generate_common_mode_emission(bits, epsilon,number_frame);

nlist    = 1 : number_fc;
flo_list = nlist * (fp/3);
delta_f_list = [12*10^3 -12*10^3];

for k = 1 :2
    delta_f = delta_f_list(k);
    for j = 1 : 4
        for i = 1:number_fc
            fc = flo_list(i);
            env_bits = digital_down_converter(common_mode_emission,output_bitnum,j,fc,Ts,sps,delta_f);
            monitor_screen(Htotal, Vtotal, env_bits, i,j,fc);
        end
    end
end


