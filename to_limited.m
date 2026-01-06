function y = to_limited(x)
y = uint8(round(16 + double(x) * (219 / 255)));
end
