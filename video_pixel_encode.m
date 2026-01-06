function [q_out, cnt] = video_pixel_encode(x, cnt, line_start)

    if line_start, cnt = 0; end

    D = logical(bitget(x, 1:8).');   
    N1D = sum(D);

    q_m = false(9, 1);
    q_m(1) = D(1);

    if (N1D > 4) || (N1D == 4 && ~D(1))
        for j = 2:8, q_m(j) = ~xor(q_m(j-1), D(j)); end
        q_m(9) = false;

    else
        for j = 2:8, q_m(j) = xor(q_m(j-1), D(j)); end
        q_m(9) = true;   
    end

    N1 = sum(q_m(1:8)); N0 = 8 - N1;
    q_out = false(10, 1);

    if cnt == 0 || N0 == N1
        q_out(10) = ~q_m(9);
        q_out(9)  = q_m(9);
        q_out(1:8) = xor(q_m(1:8), ~q_m(9));
        cnt = cnt + (q_m(9) * (N1 - N0) + (~q_m(9)) * (N0 - N1));

    else
        take_invert = (cnt > 0 && N1 > N0) || (cnt < 0 && N0 > N1);
        q_out(10) = take_invert;
        q_out(9)  = q_m(9);
        q_out(1:8) = xor(q_m(1:8), take_invert);

        if take_invert
            cnt = cnt + (2 * q_m(9)) + (N0 - N1);

        else
            cnt = cnt - (2 * ~q_m(9)) + (N1 - N0);
        end
    end
end
