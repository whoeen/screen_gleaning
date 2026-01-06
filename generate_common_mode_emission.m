function common_mode_emission = generate_common_mode_emission(bits, epsilon, number_frame)
    
    % [1] 시뮬레이션 분해능 설정
    % 이론적으로 S_dc와 공통 모드 변환은 고주파 성분이므로 높은 샘플링 필요
    upsample_rate = 40; % 1비트당 샘플 수 (충분히 높게 설정)
    dt = (1/upsample_rate) * epsilon; % 가상의 시간 간격 (simulation time step)
    
    % [2] 케이블 구조적 불균형 (Imbalance Factor Simulation)
    % 이론 문서 II.A: 도체 직경/절연 차이에 의한 불균형
    imbalance_ratio = 0.02; % 2%의 구조적 불균형 (C_p != C_n)
    
    % [3] 정전용량 매트릭스 (Maxwell Capacitance Matrix) [pF/m]
    % 구조: 3개의 페어(RGB), 각 페어는 2선(P,N) -> 총 6개의 도체
    % 순서: [R_P, R_N, G_P, G_N, B_P, B_N]
    
    % 기본 파라미터
    C_self_base = 90;    % 대지 정전용량 (Self capacitance)
    C_mutual_intra = 40; % 페어 내 상호 정전용량 (Intra-pair coupling)
    C_mutual_inter = 5;  % 페어 간 상호 정전용량 (Inter-pair crosstalk)
    
    % 6x6 매트릭스 초기화
    C_matrix = zeros(6, 6);
    
    % 매트릭스 구성
    for i = 1:3 % 3개의 페어 (R, G, B)
        idx_p = (i-1)*2 + 1;
        idx_n = (i-1)*2 + 2;
        
        % (1) Intra-Pair Coupling (페어 내부)
        % 불균형 적용: P와 N의 Self C를 다르게 설정 -> Mode Conversion 발생 원인
        C_matrix(idx_p, idx_p) = C_self_base * (1 + imbalance_ratio); 
        C_matrix(idx_n, idx_n) = C_self_base * (1 - imbalance_ratio);
        
        % 상호 정전용량 (음수로 들어가는 것이 Maxwell Matrix 정의)
        C_matrix(idx_p, idx_n) = -C_mutual_intra;
        C_matrix(idx_n, idx_p) = -C_mutual_intra;
        
        % (2) Inter-Pair Crosstalk (페어 간)
        for j = 1:3
            if i ~= j
                idx_neighbor_p = (j-1)*2 + 1;
                idx_neighbor_n = (j-1)*2 + 2;
                
                % 인접 페어와의 결합 (약한 결합)
                C_matrix(idx_p, idx_neighbor_p) = -C_mutual_inter;
                C_matrix(idx_p, idx_neighbor_n) = -C_mutual_inter;
                C_matrix(idx_n, idx_neighbor_p) = -C_mutual_inter;
                C_matrix(idx_n, idx_neighbor_n) = -C_mutual_inter;
            end
        end
    end
    
    % 대각 성분 보정 (Total C = Sum of all coupling + Self to ground)
    % Maxwell Matrix에서 대각 성분은 해당 도체에 연결된 모든 C의 합이어야 함
    for k = 1:6
        row_sum_abs = sum(abs(C_matrix(k, [1:k-1, k+1:6])));
        % 현재 대각 성분(위에서 설정한 값)을 Ground C로 간주하고 총합 재계산
        C_ground = C_matrix(k,k); 
        C_matrix(k,k) = C_ground + row_sum_abs;
    end

    % --- 2. 신호 생성 및 처리 (청크 단위로 처리) ---
    [num_channels, bit_len] = size(bits);
    % num_channels는 3 (RGB)이라고 가정
    
    % Gaussian Pulse Shaping (이전과 동일, 물리적 신호 모사)
    sigma = upsample_rate / 8;
    t_filt = -ceil(3*sigma):ceil(3*sigma);
    h_gauss = exp(-t_filt.^2 / (2*sigma^2));
    h_gauss = h_gauss / sum(h_gauss);
    
    % Intra-pair Skew 설정 (샘플 단위)
    skew_samples = round(upsample_rate * 0.05); % 5% UI Skew
    
    % 총 샘플 수 계산
    total_samples = bit_len * upsample_rate;
    
    % 청크 크기 설정 (메모리 효율성을 위해)
    % 각 청크는 약 1GB 이하로 설정 (double: 8 bytes)
    max_chunk_samples = min(1e8, floor(total_samples / 10)); % 최대 1억 샘플 또는 전체의 1/10
    if max_chunk_samples < upsample_rate * 100
        max_chunk_samples = upsample_rate * 100; % 최소 청크 크기 보장
    end
    
    % 비트 단위 청크 크기 (upsample_rate 고려)
    chunk_bits = floor(max_chunk_samples / upsample_rate);
    
    % 최종 출력을 cell array로 저장 (메모리 효율성)
    emission_chunks = cell(1, 0);
    
    % 이전 청크의 마지막 샘플들을 저장 (convolution overlap 처리용)
    overlap_samples = length(h_gauss) - 1;
    prev_chunk_end = cell(3, 1); % 각 채널별로 저장
    
    % 청크 단위로 처리
    for chunk_start = 1:chunk_bits:bit_len
        chunk_end = min(chunk_start + chunk_bits - 1, bit_len);
        chunk_bit_len = chunk_end - chunk_start + 1;
        chunk_samples = chunk_bit_len * upsample_rate;
        
        % 현재 청크의 비트 인덱스
        chunk_bit_idx = chunk_start:chunk_end;
        
        % 전압 파형 청크 초기화: [6 x Chunk_Samples]
        V_chunk = zeros(6, chunk_samples);
        
        for i = 1:3 % R, G, B 채널
            % (1) 비트 확장
            raw_bits = double(bits(i, chunk_bit_idx));
            expanded_bits = kron(raw_bits, ones(1, upsample_rate));
            
            % (2) 펄스 성형 (V_P) - overlap 처리
            if chunk_start == 1
                % 첫 번째 청크
                v_p_shaped = conv(expanded_bits, h_gauss, 'same');
            else
                % 이전 청크와의 overlap 고려
                overlap_bits = prev_chunk_end{i};
                extended_input = [overlap_bits, expanded_bits];
                v_p_conv = conv(extended_input, h_gauss, 'same');
                v_p_shaped = v_p_conv((length(overlap_bits)+1):end);
            end
            
            % 다음 청크를 위한 overlap 저장
            if chunk_end < bit_len
                prev_chunk_end{i} = expanded_bits((end-overlap_samples+1):end);
            end
            
            % (3) 차동 신호 생성 (V_N) 및 Skew 적용
            v_n_ideal = 1 - v_p_shaped;
            
            % Skew 적용 (N 라인을 지연시킴)
            v_n_skewed = [zeros(1, skew_samples), v_n_ideal(1:end-skew_samples)];
            
            % 매트릭스에 할당
            V_chunk((i-1)*2 + 1, :) = v_p_shaped;   % P line
            V_chunk((i-1)*2 + 2, :) = v_n_skewed;   % N line
        end
        
        % --- 3. 전류 계산 (Matrix Calculation) ---
        % 핵심 이론: I = C * dV/dt
        % 이 과정에서 Crosstalk와 Imbalance가 모두 계산됨
        
        % 시간 미분 (dV/dt) - 각 행에 대해 개별적으로 계산
        dV_dt_chunk = zeros(size(V_chunk));
        for i = 1:6
            dV_dt_chunk(i, :) = gradient(V_chunk(i, :)) / dt;
        end
        
        % 행렬 곱셈을 통한 전류 유도
        % I_lines: [6 x Chunk_Samples]
        I_chunk = C_matrix * dV_dt_chunk;
        
        % --- 4. 공통 모드 전류 추출 (Extract CM Current) ---
        % I_CM = I_P + I_N
        I_CM_chunk = zeros(1, chunk_samples);
        
        for i = 1:3
            idx_p = (i-1)*2 + 1;
            idx_n = (i-1)*2 + 2;
            
            % 각 페어의 공통 모드 전류
            I_CM_pair = I_chunk(idx_p, :) + I_chunk(idx_n, :);
            
            % 전체 공통 모드 전류에 합산 (Vector sum)
            I_CM_chunk = I_CM_chunk + I_CM_pair;
        end
        
        % --- 5. 방사 모델링 (Radiation) ---
        % 이론: Far-field E-field is proportional to time-derivative of CM Current
        % E ~ d(I_CM)/dt
        
        % 행 벡터로 보장
        I_CM_chunk = I_CM_chunk(:).';
        emission_chunk = gradient(I_CM_chunk) / dt;
        
        % 청크 결과를 cell array에 저장
        emission_chunks{end+1} = emission_chunk;
        
        % 메모리 정리
        clear V_chunk dV_dt_chunk I_chunk I_CM_chunk emission_chunk;
    end
    
    % 모든 청크를 결합하여 최종 출력 생성
    % cell array를 사용하여 메모리 효율적으로 결합
    if ~isempty(emission_chunks)
        % 예상 총 길이 계산
        estimated_length = sum(cellfun(@length, emission_chunks));
        estimated_length = min(estimated_length, total_samples);
        
        % 최종 출력 초기화 (실제 필요한 크기만)
        common_mode_emission = zeros(1, estimated_length);
        
        % 각 청크를 순차적으로 결합
        idx = 1;
        for k = 1:length(emission_chunks)
            chunk_data = emission_chunks{k};
            chunk_len = length(chunk_data);
            end_idx = min(idx + chunk_len - 1, estimated_length);
            actual_len = end_idx - idx + 1;
            
            if actual_len > 0
                common_mode_emission(idx:end_idx) = chunk_data(1:actual_len);
                idx = end_idx + 1;
            end
            
            if idx > estimated_length
                break;
            end
        end
        
        % 정확한 길이로 자르기
        common_mode_emission = common_mode_emission(1:min(estimated_length, total_samples));
    else
        common_mode_emission = zeros(1, total_samples);
    end
end
