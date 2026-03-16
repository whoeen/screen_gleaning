# TempestSDR — 플로우차트, 코드, 수식

> 소스: `Automation/TempestSDR/Main.java`

---

## 1. 전체 동작 플로우

```
┌─────────────────────────────────────────────────────────────────────┐
│                         애플리케이션 시작                             │
│  main() → EventQueue.invokeLater → new Main()                       │
│           ├─ new TSDRLibrary()                                       │
│           ├─ mSdrlib.registerFrameReadyCallback(this)               │
│           ├─ mSdrlib.registerValueChangedCallback(this)             │
│           └─ initialize()  [Swing GUI 구성]                          │
└─────────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      사용자 설정 단계                                  │
│                                                                      │
│  File → Load USRP  ──▶  onPluginSelected()                          │
│                              └─ mSdrlib.loadPlugin(source)          │
│                                                                      │
│  주파수 설정  ──────────▶  onCenterFreqChange()                       │
│  (spFrequency spinner)        └─ mSdrlib.setBaseFreq(freq)          │
│                                                                      │
│  해상도 / FPS 설정  ──▶  onResolutionChange(width, height, fps)      │
│  (spWidth, spHeight,          └─ mSdrlib.setResolution(height, fps) │
│   txtFramerate)                                                      │
│                                                                      │
│  게인 슬라이더  ────────▶  onGainLevelChanged()                       │
│                              └─ mSdrlib.setGain(gain)               │
│                                                                      │
│  로우패스 슬라이더  ────▶  onMotionBlurLevelChanged()                  │
│                              └─ mSdrlib.setMotionBlur(mblur)        │
└─────────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Start 버튼  →  performStartStop()                  │
│                                                                      │
│  mSdrlib.setBaseFreq(freq)                                          │
│  mSdrlib.setGain(gain)                                              │
│  mSdrlib.startAsync(height, fps)    ◀── 비동기 SDR 캡처 시작          │
└─────────────────────────────────────────────────────────────────────┘
           │  (SDR 라이브러리가 프레임마다 콜백 호출)
           ▼
┌─────────────────────────────────────────────────────────────────────┐
│              콜백 루프  (TSDRLibrary → Main)                          │
│                                                                      │
│  onFrameReady()  ──────────────────────────────────────────────────▶│
│  │  emage==true ?  ──yes──▶  resize() → ImageIO.write(out/<name>)  │
│  │  snapshot==true ? ─yes─▶  resize() → ImageIO.write(<timestamp>) │
│  └─ visualizer.drawImage(frame, image_width)   [화면 표시]           │
│                                                                      │
│  onIncommingPlot()  ──────────────────────────────────────────────▶│
│  │  FRAME plot  ──▶  frame_plotter.plot()                           │
│  │               if AUT: auto_resolution_fps_id = 최대값 인덱스       │
│  │  LINE plot   ──▶  line_plotter.plot()                            │
│  │               if AUT: fps + height 계산 → 3회 수렴 확인           │
│  └──────────────────────────────────────────────────────────────────│
│                                                                      │
│  onValueChanged()                                                   │
│  ├─ PLL_FRAMERATE       → setFramerateValButDoNotSyncWithLibrary()  │
│  ├─ AUTOCORRECT_RESET   → btnReset 해제                              │
│  ├─ FRAMES_COUNT        → lblFrames 업데이트                         │
│  └─ AUTOGAIN            → autoScaleVisualizer.setValue()            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 2. 자동 측정 (WebSocket 연동) 플로우

`Tweaks → Connect to server` 클릭 시 `connectToServer()` 실행.

```
TempestSDR (Main.java)              server.js               webpage/index.html
       │                                │                           │
       │  WebSocket 연결                 │                           │
       │──── ws://127.0.0.1:8081/2 ────▶│                           │
       │                                │                           │
       │  ready==1 일 때 (3초마다)        │                           │
       │──── ["1", "next"] ────────────▶│──── ["2", "next"] ───────▶│
       │                                │                           │ 다음 이미지 표시
       │                                │◀─── ["1", "img_filename"]─│
       │◀─── ["2", "img_filename"] ─────│                           │
       │                                │                           │
       │  emageFilename = "img_filename"│                           │
       │  takeEmage = 1                 │                           │
       │  (3초 후)                       │                           │
       │  emageFilenameComplete = filename + numEmages              │
       │  emage = true  ─────────────────────────────────────────▶  │
       │                                                onFrameReady() 에서 저장
       │  numEmages-- (1→0→-1)                                      │
       │  numEmages < 0: ready=1 (다음 이미지 요청)                   │
       │                                                            │
       │  counter < 400 까지 반복                                    │
```

### 상태 변수

| 변수 | 초기값 | 역할 |
|------|--------|------|
| `ready` | 1 | 1 = 다음 이미지 요청 가능 |
| `takeEmage` | 0 | 1 = 프레임 저장 대기 중 |
| `numEmages` | 10 | 저장할 프레임 수 (서버 응답 시 1로 재설정) |
| `counter` | 0 | 총 저장된 emage 수 (최대 400) |
| `emage` | false | true 이면 onFrameReady()에서 파일 저장 |

---

## 3. 핵심 수식

### 3-1. FPS ↔ 인덱스 변환

자동상관(autocorrelation) 플롯에서 **FRAME 피크 인덱스** → **FPS** 변환:

```
fps = samplerate / (offset + id)
```

역변환 (FPS → 플롯 인덱스):
```
id = round( samplerate / fps ) - offset
```

**코드** (`fps_transofmer`, line 1419–1444):
```java
// 인덱스 → FPS
public double fromIndex(int id, int offset, long samplerate) {
    return samplerate / (double) (offset + id);
}

// FPS → 인덱스
public int toIndex(double val, int offset, long samplerate) {
    return roundData(samplerate / val - offset);
}
```

---

### 3-2. 비디오 높이 ↔ 인덱스 변환

**LINE 플롯** 피크 인덱스 → **Height (픽셀)** 변환:

```
linelength = offset + id          (샘플 단위 한 라인 길이)
height = frame_length / linelength
```

`frame_length`는:
- AUT 모드: `frame_length = fps_id + fps_offset`  (FPS 자동탐지값 사용)
- 일반 모드: `frame_length = samplerate / framerate`

**수식 정리:**
```
height = (samplerate / fps) / (offset + id)
       = samplerate / (fps × (offset + id))
```

역변환:
```
id = round( frame_length / height ) - offset
```

**코드** (`TransformerAndCallbackHeight`, line 1464–1486):
```java
// 인덱스 + 명시적 frame_length → 높이
public double fromIndexAndLength(int id, int offset, long samplerate, double length) {
    final double linelength = offset + id;
    return length / linelength;
}

// 인덱스 → 높이 (frame_length = samplerate/framerate 사용)
public double fromIndex(int id, int offset, long samplerate) {
    return fromIndexAndLength(id, offset, samplerate,
        (this.length == null) ? (samplerate / framerate) : this.length);
}

// 높이 → 인덱스
public int toIndex(double val, int offset, long samplerate) {
    final double length = (this.length == null) ? (samplerate / framerate) : this.length;
    return roundData(length / val - offset);
}
```

---

### 3-3. 높이-FPS 연동 잠금 (Lock "L" 버튼)

높이를 변경할 때 FPS도 비례적으로 조정:

```
new_fps = old_fps × old_height / new_height
```

**코드** (line 548–549):
```java
if (tglbtnLockHeightAndFramerate.isSelected() && !height_change_from_auto)
    onResolutionChange(width, newheight, framerate * oldheight / (double) newheight);
```

**의미:** 스크린 라인 수가 달라져도 픽셀 클럭(samples/pixel)은 유지.

---

### 3-4. 게인 정규화

슬라이더 값 → [0.0, 1.0] 범위로 정규화:

```
gain = (slider_value - min) / (max - min)
```

**코드** (line 876–877, 987–988):
```java
float gain = (slGain.getValue() - slGain.getMinimum())
           / (float)(slGain.getMaximum() - slGain.getMinimum());
if (gain < 0.0f) gain = 0.0f;
else if (gain > 1.0f) gain = 1.0f;
```

---

### 3-5. 로우패스(Motion Blur) 강도

```
mblur = slider_value / 100.0
```

**코드** (line 999):
```java
float mblur = slMotionBlur.getValue() / 100.0f;
```

---

### 3-6. 프레임레이트 증감 스텝

버튼 (`<` / `>`) 을 오래 누를수록 스텝 크기 가속:

```
amount = clicks² × FRAMERATE_MIN_CHANGE
FRAMERATE_MIN_CHANGE = 1 / 10^8 = 10⁻⁸

amount = min(clicks² × 10⁻⁸,  0.05)
```

**코드** (line 1112–1119):
```java
private static final int FRAMERATE_SIGNIFICANT_FIGURES = 8;
private static final double FRAMERATE_MIN_CHANGE = 1.0 / Math.pow(10, FRAMERATE_SIGNIFICANT_FIGURES);

double amount = clicksofar * clicksofar * FRAMERATE_MIN_CHANGE;
if (amount > 0.05) amount = 0.05;
if (left && framerate > amount)
    framerate -= amount;
else if (!left)
    framerate += amount;
```

---

### 3-7. 자동 해상도 탐지 수렴 조건 (AUT 버튼)

`AUTO_FRAMERATE_CONVERGANCE_ITERATIONS = 3`

같은 `(fps, height)` 쌍이 **3회 연속** 탐지되면 해당 값을 채택:

```
key = (long)(fps × height)   [해시]

if count[key] == 3:
    onResolutionChange(fps, height)
    auto_resolution = false
```

**코드** (line 1346–1388):
```java
private Long hashHeightAndFPS(double fps, int height) {
    return (Long)(long)(fps * height);
}

// ...
Integer value = auto_resolution_map.get(key);
if (value != null && value == AUTO_FRAMERATE_CONVERGANCE_ITERATIONS) {
    onResolutionChange(fps, height, "Detected %s");
    btnAutoResolution.setSelected(false);
    auto_resolution = false;
} else {
    if (value == null) value = 0;
    value++;
    auto_resolution_map.put(key, value);
}
```

---

## 4. 컴포넌트 간 콜백 관계도

```
┌──────────────┐   registerFrameReadyCallback    ┌──────────────────┐
│  TSDRLibrary │ ──────────────────────────────▶ │                  │
│  (native C)  │   onFrameReady(lib, frame)       │   Main.java      │
│              │ ◀────────────────────────────── │   (Java GUI)     │
│              │                                  │                  │
│              │   registerValueChangedCallback   │                  │
│              │ ──────────────────────────────▶ │                  │
│              │   onValueChanged(id, arg0, arg1) │                  │
│              │ ◀────────────────────────────── │                  │
│              │                                  │                  │
│              │   onIncommingPlot(id, data, ...)  │                  │
│              │ ──────────────────────────────▶ │                  │
└──────────────┘                                  └──────────────────┘
                                                         │
                              ┌──────────────────────────┤
                              │                          │
                    ┌─────────▼──────┐        ┌─────────▼──────────┐
                    │ ImageVisualizer │        │  PlotVisualizer     │
                    │ (화면 표시)      │        │  frame_plotter      │
                    └────────────────┘        │  line_plotter       │
                                              └────────────────────┘
                                                         │
                                              fps_transofmer.fromIndex()
                                              height_transformer.fromIndex()
```

---

## 5. onFrameReady() — emage 저장 상세 흐름

```
onFrameReady(lib, frame)
      │
      ├─ emage == true?
      │       yes ──▶  emage = false
      │                resize(frame, image_width, frame.getHeight())
      │                   └─ Bilinear 보간 리사이즈
      │                File outputfile = new File("out/" + emageFilenameComplete)
      │                ImageIO.write(resized_frame, "png", outputfile)
      │                visualizer.setOSD("Saved to " + path, 2000ms)
      │
      ├─ snapshot == true?
      │       yes ──▶  snapshot = false
      │                resize(frame, image_width, frame.getHeight())
      │                String filename = "TSDR_<yyyy-MM-dd_HH-mm-ss>_<freq>MHz.png"
      │                ImageIO.write(resized_frame, "png", new File(filename))
      │
      └─ visualizer.drawImage(frame, image_width)   [항상 실행: 화면 갱신]
```

### 리사이즈 수식

```
출력 크기: image_width × frame.getHeight()
    image_width = spWidth.getValue()  (GUI 설정값)
```

**코드** (line 1181–1193):
```java
private static BufferedImage resize(BufferedImage image, int width, int height) {
    BufferedImage resizedImage = new BufferedImage(width, height, image.getType());
    Graphics2D g = resizedImage.createGraphics();
    g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                       RenderingHints.VALUE_INTERPOLATION_BILINEAR);
    g.setRenderingHint(RenderingHints.KEY_RENDERING,
                       RenderingHints.VALUE_RENDER_QUALITY);
    g.setRenderingHint(RenderingHints.KEY_ANTIALIASING,
                       RenderingHints.VALUE_ANTIALIAS_ON);
    g.drawImage(image, 0, 0, width, height, null);
    g.dispose();
    return resizedImage;
}
```

---

## 6. 파라미터 요약표

| 파라미터 | GUI 위치 | 기본값 | 단위 |
|---------|---------|--------|------|
| 중심 주파수 | spFrequency | 400,000,000 | Hz |
| 주파수 스텝 | — | 5,000,000 | Hz |
| 비디오 너비 | spWidth | 576 | px |
| 비디오 높이 | spHeight | 625 | px |
| 프레임레이트 | txtFramerate | 25 | fps |
| 게인 | slGain | 0.5 (50%) | [0,1] |
| 로우패스 | slMotionBlur | 0.0 | [0,1] |
| 수렴 반복 수 | — | 3 | 회 |
| 최대 emage 수 | — | 400 | 장 |
| WebSocket 포트 | — | 8081 | — |
| 저장 형식 | — | png | — |
