# Emage 복원 — 수학적 원리

> TempestSDR (`Main.java`) + Recognition (`utils.py`) 코드 기반

---

## 0. 전체 파이프라인 개요

```
스마트폰 화면
    │  픽셀 구동 전류 → EM 방사
    ▼
안테나 + USRP (SDR)
    │  RF 신호 수신·복조
    ▼
1차원 시계열 x[n]      ← "샘플 스트림"
    │  자동상관 → 주기 탐지
    ▼
2차원 이미지 재구성     ← "emage"
    │  CNN 분류
    ▼
복원된 텍스트/숫자
```

---

## 1. EM 신호 모델

LCD/OLED 디스플레이는 픽셀 클럭(pixel clock) 주파수와 그 고조파에서 EM 방사를 방출한다.
디스플레이 타이밍 파라미터:

| 기호 | 의미 |
|------|------|
| W    | 수평 전체 픽셀 수 (blanking 포함) |
| H    | 수직 전체 라인 수 (blanking 포함) |
| fps  | 초당 프레임 수 |

```
픽셀 클럭  f_pix = W × H × fps          [Hz]
라인 주기  T_line = 1 / (H × fps)        [초]
프레임 주기 T_frame = 1 / fps             [초]
```

수신 신호를 복조하면 픽셀 밝기에 비례하는 1D 시계열을 얻는다:

```
x[n] = Σ_k  h[k] · p[n−k]  +  w[n]

  p[n] : n번째 샘플 시점의 픽셀 밝기
  h[k] : 채널 임펄스 응답 (안테나 + SDR 전달함수)
  w[n] : 가산 잡음
```

SDR 샘플레이트를 `f_s`라 하면, 샘플 단위 주기는:

```
N_frame = f_s / fps                      [samples/frame]
N_line  = f_s / (fps × H)  =  N_frame / H   [samples/line]
```

---

## 2. 자동상관(Autocorrelation)으로 주기 탐지

### 2-1. 이산 자동상관 정의

```
R[τ] = (1/N) Σ_{n=0}^{N−1}  x[n] · x[n+τ]
```

신호 x[n]이 주기 T를 가지면 `R[T] ≈ R[0]` (최대값).

따라서:
- `R[τ]`의 **FRAME 피크** 위치 τ* = `N_frame` → fps 결정
- `R[τ]`의 **LINE 피크** 위치 τ** = `N_line` → height 결정

### 2-2. 코드에서의 인덱스 ↔ 물리량 변환

TSDRLibrary가 `onIncommingPlot()`으로 자동상관 배열 `data[]`을 전달.
배열 인덱스 `id`, 플롯 시작 오프셋 `offset`이 주어질 때:

```
τ* = offset + id        [samples]
```

**FPS 계산:**

```
fps = f_s / τ*
    = f_s / (offset + id)
```

코드 (`Main.java:1420`):
```java
public double fromIndex(int id, int offset, long samplerate) {
    return samplerate / (double)(offset + id);
}
```

역변환 (fps → 플롯 인덱스):
```
id = round(f_s / fps) − offset
```

코드 (`Main.java:1444`):
```java
public int toIndex(double val, int offset, long samplerate) {
    return roundData(samplerate / val - offset);
}
```

**Height 계산:**

LINE 피크 인덱스 `id_L`로부터:

```
N_line = offset_L + id_L            [samples/line]
N_frame = offset_F + id_F           [samples/frame]  ← FRAME 피크

height = N_frame / N_line
       = (offset_F + id_F) / (offset_L + id_L)
```

코드 (`Main.java:1371, 1464-1467`):
```java
// AUT 모드: N_frame = fps_id + fps_offset (FRAME 피크값)
final int height = roundData(
    height_transformer.fromIndexAndLength(
        line_plotter.getMaxIndex(),
        line_plotter.getOffset(),
        samplerate,
        auto_resolution_fps_id + auto_resolution_fps_offset  // N_frame
    )
);

// 내부 계산
public double fromIndexAndLength(int id, int offset, long samplerate, double length) {
    final double linelength = offset + id;   // N_line
    return length / linelength;              // N_frame / N_line = height
}
```

일반 모드 (FPS 수동 설정 시):
```
N_frame = f_s / fps

height = (f_s / fps) / (offset_L + id_L)
```

코드 (`Main.java:1472`):
```java
public double fromIndex(int id, int offset, long samplerate) {
    return fromIndexAndLength(id, offset, samplerate,
        (this.length == null) ? (samplerate / framerate) : this.length);
}
```

### 2-3. AUT 수렴 조건

동일한 `(fps, height)` 쌍이 **3회 연속** 탐지되면 확정:

```
key = (long)(fps × height)       ← 해시

count[key]++ 마다 반복
count[key] == 3 이면 → onResolutionChange(fps, height) 호출
```

코드 (`Main.java:1346-1386`):
```java
private Long hashHeightAndFPS(double fps, int height) {
    return (Long)(long)(fps * height);
}

if (value != null && value == AUTO_FRAMERATE_CONVERGANCE_ITERATIONS) {   // 3
    onResolutionChange(fps, height, "Detected %s");
    auto_resolution = false;
}
```

---

## 3. 2D 이미지 재구성 (Frame Reconstruction)

자동상관으로 `N_frame`, `H` (height)를 결정한 뒤, 1D 스트림을 2D로 재배열:

```
x[n]  →  image[row, col]

  row = floor(n / N_line)  mod H        = floor(n × H / N_frame)  mod H
  col = n  mod  N_line                  = n  mod  (N_frame / H)
```

결과 이미지 크기:
```
height (행) = H
width  (열) = N_line  (= N_frame / H)
```

이후 GUI 너비 `image_width`에 맞게 bilinear 리사이즈:

```
image_out = resize(frame, image_width, frame.getHeight())
```

코드 (`Main.java:1200`):
```java
final BufferedImage resized_frame = resize(frame, image_width, frame.getHeight());
```

`resize()` 내부 — bilinear 보간:
```
p'(x, y) = Σ_{i,j} p(i,j) · max(0, 1−|x−i|) · max(0, 1−|y−j|)
```

코드 (`Main.java:1186`):
```java
g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                   RenderingHints.VALUE_INTERPOLATION_BILINEAR);
```

---

## 4. 로우패스 필터 (동기화 전처리)

`Lowpass before sync detection` 옵션 활성 시 TSDRLibrary가 자동상관 탐지 전에 저역통과 필터를 적용.

일반적인 이동평균(moving average) 형태:

```
y[n] = (1/M) Σ_{k=0}^{M−1} x[n−k]

전달함수:  H(z) = (1/M) · (1 − z^{−M}) / (1 − z^{−1})
```

코드 트리거 (`Main.java:465`):
```java
mSdrlib.setParam(PARAM.LOW_PASS_BEFORE_SYNC, enabled ? 1 : 0);
```

---

## 5. Motion Blur (프레임 평균화)

연속 프레임들을 지수이동평균(EMA)으로 혼합해 SNR 향상:

```
I_out[t] = (1 − α) · I_out[t−1]  +  α · I_raw[t]

  α = mblur = slider_value / 100.0
```

α → 0: 이전 프레임 비중 증가 (더 많이 평균화, 잔상 증가)
α → 1: 현재 프레임만 사용

코드 (`Main.java:999`):
```java
float mblur = slMotionBlur.getValue() / 100.0f;
mSdrlib.setMotionBlur(mblur);
```

---

## 6. CNN 분류 — LeNet_EMAGE

복원된 emage에서 각 자릿수를 독립적으로 분류.

### 6-1. 입력 전처리 (정규화)

```
x_norm = (x_raw − μ) / σ
```

| 기기 | μ (mean) | σ (std) |
|------|----------|---------|
| iPhone 6S | 0.1545 | 0.0489 |
| iPhone 6  | 0.2933 | 0.0546 |
| Honor 6X  | 0.4303 | 0.0315 |

코드 (`utils.py:17-21`):
```python
data_transform_iph6s = transforms.Compose([
    transforms.Grayscale(num_output_channels=1),
    transforms.ToTensor(),
    transforms.Normalize([0.1545], [0.0489]),
])
```

### 6-2. 이미지 크롭 (자릿수 분리)

6자리 보안코드 → 6개 패치로 분할:

**iPhone 6 / 6S** (전체 120×31 px → 각 20×31 px):
```
pin_k = crop(img, x_start=(k−1)×20, y=0, width=20, height=31)
      k = 1, 2, 3, 4, 5, 6
```

**Honor 6X** (전체 126×45 px → 각 21×45 px):
```
pin_k = crop(img, x_start=(k−1)×21, y=0, width=21, height=45)
```

코드 (`utils.py:115-122`):
```python
img_kou = img_kou.resize((120, 31))
pin1 = img_kou.crop((0,   0, 20,  31))
pin2 = img_kou.crop((20,  0, 40,  31))
pin3 = img_kou.crop((40,  0, 60,  31))
pin4 = img_kou.crop((60,  0, 80,  31))
pin5 = img_kou.crop((80,  0, 100, 31))
pin6 = img_kou.crop((100, 0, 120, 31))
```

### 6-3. LeNet_EMAGE 구조 (iPhone 6/6S)

입력: `1 × 20 × 31`

```
Layer 1 — Conv2d(1→6, kernel=5×5)
  출력 크기: 6 × (20−5+1) × (31−5+1) = 6 × 16 × 27
  연산: f1[c,i,j] = ReLU( Σ_{kh,kw} W1[c,kh,kw] · x[i+kh, j+kw] + b1[c] )

Layer 2 — MaxPool2d(2×2)
  출력 크기: 6 × 8 × 13

Layer 3 — Conv2d(6→16, kernel=5×5)
  출력 크기: 16 × (8−5+1) × (13−5+1) = 16 × 4 × 9
  단, 실제로는 16 × 2 × 4 = 128개 특징

Layer 4 — MaxPool2d(2×2)
  출력 크기: 16 × 2 × 4  →  flatten → 128

FC1: Linear(128 → 120)  + ReLU
FC2: Linear(120 → 84)   + ReLU
FC3: Linear(84  → 10)   ← logit (클래스 0~9)
```

**합성곱 수식:**

```
f_out[c_out, i, j] = ReLU(
    Σ_{c_in=0}^{C−1}
    Σ_{kh=0}^{K−1}
    Σ_{kw=0}^{K−1}
        W[c_out, c_in, kh, kw] · f_in[c_in, i+kh, j+kw]
    + b[c_out]
)
```

**Max Pooling 수식:**

```
p[c, i, j] = max_{di,dj ∈ {0,1}}  f_out[c, 2i+di, 2j+dj]
```

코드 (`utils.py:51-69`):
```python
class LeNet_EMAGE_iph6(nn.Module):
    def __init__(self):
        self.conv1 = nn.Conv2d(1, 6, 5)    # 1→6 채널, 5×5 커널
        self.conv2 = nn.Conv2d(6, 16, 5)   # 6→16 채널, 5×5 커널
        self.fc1   = nn.Linear(128, 120)
        self.fc2   = nn.Linear(120, 84)
        self.fc3   = nn.Linear(84, 10)     # 10-class (0~9)

    def forward(self, x):
        out = F.relu(self.conv1(x))
        out = F.max_pool2d(out, 2)
        out = F.relu(self.conv2(out))
        out = F.max_pool2d(out, 2)
        out = out.view(out.size(0), -1)    # flatten
        out = F.relu(self.fc1(out))
        out = F.relu(self.fc2(out))
        out = self.fc3(out)                # logit 출력
        return out
```

Honor 6X는 입력 패치가 `21×45`로 더 커서 flatten 후 `256` 노드:

```python
self.fc1 = nn.Linear(256, 120)   # 256 = 16 × 4 × 4
```

### 6-4. 예측

```
ŷ = argmax_k  logit[k]
```

코드 (`utils.py:127`):
```python
int(torch.max(model(data_transforms_t(pin1).unsqueeze(0).to(device)), 1)[1]
    .cpu().data.numpy())
```

### 6-5. 정확도 측정

6자리 전체 중 맞춘 자릿수 비율:

```
digit_accuracy = corr / base
               = (맞춘 자릿수 합) / (총 자릿수)
               = Σ_i Σ_k 1[ŷ_{i,k} == y_{i,k}]
                 ─────────────────────────────
                        N_samples × 6
```

코드 (`utils.py:143-148`):
```python
corr += res    # res = 이미지 하나에서 맞춘 자릿수 (0~6)
base += 6
return (corr / base)
```

---

## 7. 수식 종합 요약

| 단계 | 수식 | 코드 위치 |
|------|------|-----------|
| FPS 탐지 | `fps = f_s / (offset + id)` | `Main.java:1420` |
| Height 탐지 | `H = N_frame / N_line` | `Main.java:1464` |
| 1D→2D 재배열 | `row = ⌊n·H/N_frame⌋ mod H` | TSDRLibrary (native) |
| Bilinear 리사이즈 | `p'(x,y) = Σ p(i,j)·w_i·w_j` | `Main.java:1186` |
| Motion Blur EMA | `I_out = (1−α)·I_prev + α·I_raw` | `Main.java:999` |
| 정규화 | `x̂ = (x − μ) / σ` | `utils.py:20` |
| 크롭 | `pin_k = img[:, (k-1)·w : k·w]` | `utils.py:117` |
| 합성곱 | `f = ReLU(W * x + b)` | `utils.py:61` |
| Max Pooling | `p = max_{2×2}(f)` | `utils.py:62` |
| 분류 | `ŷ = argmax logit` | `utils.py:127` |
| 자릿수 정확도 | `acc = corr / (N × 6)` | `utils.py:148` |
