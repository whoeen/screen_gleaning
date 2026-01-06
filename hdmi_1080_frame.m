function bits = hdmi_1080_frame(video,number_frame)
  
    Hact = 1920; Hfp = 88; Hsync = 44; Hbp = 148; Htot = 2200;
    Vact = 1080; Vfp = 4;  Vsync = 5;  Vbp = 36;  Vtot = 1125;
    fref = 60; 
    
    frame_bits = false(3, Vtot * Htot * 10); 
    line_pointer = 1; 
    cnt = [0, 0, 0];
   
    CTL = {
        fliplr([1 1 0 1 0 1 0 1 0 0]).';  
        fliplr([0 0 1 0 1 0 1 0 1 1]).';  
        fliplr([0 1 0 1 0 1 0 1 0 0]).';  
        fliplr([1 0 1 0 1 0 1 0 1 1]).';  
    };
    c00 = CTL{1}; 

    for v = 1:Vtot     
        Line0 = false(10, Htot);   
        Line1 = false(10, Htot);
        Line2 = false(10, Htot);

        if v <= Vfp
          
            VS = 0; HS = 0;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0 = repmat(ctl0, 1, Htot);
            Line1 = repmat(c00, 1, Htot);
            Line2 = repmat(c00, 1, Htot);

        elseif v <= Vfp + Vsync
            
            VS = 1; HS = 0;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0 = repmat(ctl0, 1, Htot);
            Line1 = repmat(c00, 1, Htot);
            Line2 = repmat(c00, 1, Htot);

        elseif v <= Vfp + Vsync + Vbp
            
            VS = 0; HS = 0;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0 = repmat(ctl0, 1, Htot);
            Line1 = repmat(c00, 1, Htot);
            Line2 = repmat(c00, 1, Htot);

        else
            
            h_pointer = 1;

            HS = 0; VS = 0;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0(:, h_pointer:h_pointer+Hfp-1) = repmat(ctl0, 1, Hfp);
            Line1(:, h_pointer:h_pointer+Hfp-1) = repmat(c00, 1, Hfp);
            Line2(:, h_pointer:h_pointer+Hfp-1) = repmat(c00, 1, Hfp);
            h_pointer = h_pointer + Hfp;

            HS = 1;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0(:, h_pointer:h_pointer+Hsync-1) = repmat(ctl0, 1, Hsync);
            Line1(:, h_pointer:h_pointer+Hsync-1) = repmat(c00, 1, Hsync);
            Line2(:, h_pointer:h_pointer+Hsync-1) = repmat(c00, 1, Hsync);
            h_pointer = h_pointer + Hsync;
         
            HS = 0;
            key = sprintf('%d%d', HS, VS);
            switch key
                case '00', ctl0 = CTL{1};
                case '01', ctl0 = CTL{2};
                case '10', ctl0 = CTL{3};
                case '11', ctl0 = CTL{4};
            end
            Line0(:, h_pointer:h_pointer+Hbp-1) = repmat(ctl0, 1, Hbp);
            Line1(:, h_pointer:h_pointer+Hbp-1) = repmat(c00, 1, Hbp);
            Line2(:, h_pointer:h_pointer+Hbp-1) = repmat(c00, 1, Hbp);
            h_pointer = h_pointer + Hbp;
           
            for h = 1:Hact
                pix_index = (v-(Vfp+Vsync+Vbp)-1)*Hact + h;
                [Line0(:, h_pointer+h-1), cnt(1)] = video_pixel_encode(video(1, pix_index), cnt(1), h==1);
                [Line1(:, h_pointer+h-1), cnt(2)] = video_pixel_encode(video(2, pix_index), cnt(2), h==1);
                [Line2(:, h_pointer+h-1), cnt(3)] = video_pixel_encode(video(3, pix_index), cnt(3), h==1);
            end
        end

        
        bitnum_line = numel(Line0);
        frame_bits(1, line_pointer:line_pointer+bitnum_line-1) = Line0(:).';
        frame_bits(2, line_pointer:line_pointer+bitnum_line-1) = Line1(:).';
        frame_bits(3, line_pointer:line_pointer+bitnum_line-1) = Line2(:).';
        line_pointer = line_pointer + bitnum_line;
    end

    bits = repmat(frame_bits,1,number_frame);
end
