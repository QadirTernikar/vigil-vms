# Vigil VMS Project

A professional-grade Video Management System (VMS) built with Flutter, designed for robust security monitoring.

## Features

*   **Live Monitoring**: Low-latency streaming via Go2RTC.
*   **Recording System**:
    *   Dynamic stream registration.
    *   Segment-based recording (10-minute chunks).
    *   API-driven Recording Controller.
*   **Playback & Evidence**:
    *   Timeline-based playback with visual scrubbing.
    *   Snapshot gallery with camera-name organization.
    *   Forensic integrity (strict naming conventions).
*   **Architecture**:
    *   Flutter (Windows/Linux/Android) frontend.
    *   Dart-based Gateway (Recording & Playback servers).
    *   Go2RTC integration for RTSP/WebRTC handling.
    *   Supabase integration options.

## Prerequisites

*   **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install/windows) (Ensure `flutter doctor` is healthy).
*   **VS Code**: with Flutter/Dart extensions.
*   **Go2RTC**: The project requires the Go2RTC binary.

## Setup Instructions

### 1. Clone the Repository
```bash
git clone <repository-url>
cd mmvs/vigil_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Setup Go2RTC
The `go2rtc` binary is **not** included in the repository (to keep it clean).
1.  Download the latest `go2rtc.exe` (for Windows) or binary from [Go2RTC Releases](https://github.com/AlexxIT/go2rtc/releases).
2.  Place the binary in the `vigil_app/go2rtc/` folder.
    *   Windows: `vigil_app/go2rtc/go2rtc.exe`

### 4. Setup FFMPEG (Optional/If needed)
If the app requires local FFmpeg for specific tasks (like transcoding):
1.  Download FFmpeg essentials build.
2.  Extract to `vigil_app/ffmpeg/` or ensure it's in your system PATH.
    *   *Note: The app may expect a specific path structure if hardcoded.*

## How to Run

### Windows (Quick Start)
We have provided a batch script to start all backend services:

1.  Open a terminal in `vigil_app`.
2.  Run the startup script:
    ```cmd
    start_all.bat
    ```
    This script will launch:
    *   Go2RTC (Port 1984)
    *   Recording Server (Port 8091)
    *   Playback Server (Port 8090)

3.  In a separate terminal, run the Flutter app:
    ```bash
    flutter run -d windows
    ```

### Manual Start (Mac/Linux)
1.  Start Go2RTC:
    ```bash
    cd go2rtc && ./go2rtc
    ```
2.  Start Recording Server:
    ```bash
    dart run gateway/recording_server.dart
    ```
3.  Start Playback Server:
    ```bash
    dart run gateway/playback_server.dart
    ```
4.  Run App:
    ```bash
    flutter run -d linux
    ```

## Project Structure
*   `vigil_app/lib`: Flutter UI code.
*   `vigil_app/gateway`: Dart backend servers (Recording, Playback).
*   `vigil_app/go2rtc`: Go2RTC config and binary location.
