# Screen Gleaning — Project Hierarchy

This document describes the overall architecture and component hierarchy of the Screen Gleaning project.

## Repository Structure

```
screen_gleaning/
├── Analysis/          # Synthetic dataset generation
├── Automation/        # Hardware integration & data collection
└── Recognition/       # Deep learning model training & evaluation
```

---

## Top-level Pipeline

The three top-level directories correspond to the three sequential phases of the research pipeline:

```
Analysis/          →       Automation/          →       Recognition/
(generate test           (collect emages from          (train models &
 images)                  phone emissions)              evaluate results)
```

---

## 1. Analysis/ — Image Generation

Generates synthetic test images that are displayed on the phone screen during measurement.

```
Analysis/
└── ImageGeneration/
    ├── Letter/        # Eye doctor letter charts (C D E F L N O P T Z)
    │   ├── letter_autom.sh         # Bash automation script
    │   ├── xetexMakeLetter.tex     # LaTeX template
    │   └── Sloan.otf               # Sloan eye-chart font
    │
    ├── SMS/           # Simulated SMS security codes (6-digit)
    │   ├── sms_autom.sh
    │   ├── xetexMakeSMS.tex
    │   └── HelveticaNeue*.otf
    │
    └── Grid/          # 40×40 random digit grids
        ├── grid_autom.sh
        └── xetexMakeSMS_gray.tex
```

**Build chain:** `Bash script → XeLaTeX (.tex) → PDF → ImageMagick → JPG`

---

## 2. Automation/ — Data Collection

Controls hardware and synchronizes image display with electromagnetic capture.

```
Automation/
├── TempestSDR/                    # USRP radio capture GUI (Java)
│   └── Main.java                  # Swing GUI (1 493 lines)
│       ├── USRP parameter control (frequency, sample rate, resolution)
│       ├── Automatic line-rate detection ("AUT" button)
│       └── "Tweaks → connect to server" triggers automated capture
│
├── js-server/
│   ├── client-server-sockets/     # WebSocket relay server (Node.js)
│   │   ├── server.js              # Listens on port 8081
│   │   │   ├── Maintains user-ID connection registry
│   │   │   └── Forwards JSON messages: [toUserID, text]
│   │   └── public/
│   │       ├── index.html         # Demo page
│   │       └── app.js             # Client-side WebSocket connect
│   └── readme.md
│
└── webpage/
    └── index.html                 # Full-screen display client (browser)
        ├── Connects to ws://10.0.0.2:8081
        ├── Loads JPG images from local directory listing
        └── Shows next image on "next" WebSocket command
```

**Communication flow:**
```
TempestSDR GUI  ──WebSocket──▶  server.js  ──WebSocket──▶  webpage/index.html
(measurement)                  (relay)                     (display on phone)
```

---

## 3. Recognition/ — Model Training & Evaluation

PyTorch pipeline for training and testing deep learning models on captured emages.

```
Recognition/
├── config.py          # Dataset paths & hyperparameters per device/task
│   ├── Config_eyedoctor            (ResNet18, eye doctor letters)
│   ├── Config_securitycode_iph6s   (LeNet_EMAGE, iPhone 6S)
│   ├── Config_securitycode_iph6    (LeNet_EMAGE, iPhone 6)
│   └── Config_securitycode_honor   (LeNet_EMAGE, Honor 6X)
│
├── utils.py           # Network architectures & data preprocessing
│   ├── LeNet_EMAGE_iph6            (CNN, iPhone 6 / 6S)
│   ├── LeNet_EMAGE_honor           (CNN, Honor 6X)
│   ├── evaluate()                  (accuracy on dataset)
│   ├── security_test()             (per-digit recognition, 6-digit crop)
│   └── security_test_honor()
│
├── train_eyedoctor.py              # ResNet18 training
├── train_securitycode_iph6s.py     # LeNet_EMAGE training (iPhone 6S)
├── train_securitycode_iph6.py      # LeNet_EMAGE training (iPhone 6)
├── train_securitycode_honor6x.py   # LeNet_EMAGE training (Honor 6X)
│
├── test_security_code.py           # Comprehensive evaluation
│   ├── Cross-device accuracy
│   ├── Cross-magazine accuracy
│   ├── Robustness to noise
│   └── Inter-session generalization
│
├── checkpoints/       # Saved model weights
│   ├── eyed_best.tar  (eye doctor)
│   ├── secpin_6s_best.tar
│   ├── secpin_6_best.pth
│   └── secpin_honor_best.pth
│
└── data/              # Downloaded emage datasets (not in repo)
    ├── eyedoctor/T4/{train,val,test}/
    └── security_code/{iphone6s,iphone6,honor6x}/
```

### Model Hierarchy

```
Task: Eye Doctor Letter Recognition
└── ResNet18
    ├── Input:  224×224 RGB image
    └── Output: 10 classes (C D E F L N O P T Z)

Task: Security Code Recognition
└── LeNet_EMAGE
    ├── Input:  full-code grayscale image
    │   ├── iPhone 6/6S: 120×31 px  →  crop 6 × (20×31) patches
    │   └── Honor 6X:    126×45 px  →  crop 6 × (21×45) patches
    └── Output: 10 digit classes per patch (0–9)  ×  6 positions
```

### Device-specific Normalization

| Device    | Mean   | Std    |
|-----------|--------|--------|
| iPhone 6S | 0.1545 | 0.0489 |
| iPhone 6  | 0.2933 | 0.0546 |
| Honor 6X  | 0.4303 | 0.0315 |
| Eye doctor| 0.2968 | 0.1310 |

---

## End-to-End Data Flow

```
1. Analysis/
   Generate JPG images (letters / security codes / grids)
           │
           ▼
2. Automation/
   Display images full-screen on phone (webpage/index.html)
   Capture EM emissions with USRP (TempestSDR/Main.java)
   Synchronize via WebSocket relay (js-server/server.js)
   → Raw emage captures saved as dataset
           │
           ▼
3. Recognition/
   Load emage dataset (Recognition/data/)
   Train CNN model (train_*.py)
   Evaluate accuracy across sessions/devices (test_security_code.py)
   → Results reproduce Table VI of the Screen Gleaning paper
```
