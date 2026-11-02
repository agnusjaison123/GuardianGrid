# GuardianGrid Mobile

## Run Backend (Terminal 1)

```powershell
cd C:\GuardianGrid\backend
if (!(Test-Path .venv)) { py -3.11 -m venv .venv }
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Quick check:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

Expected output: `{"status":"ok"}`

## Run Flutter App (Terminal 2)

```powershell
cd C:\GuardianGrid\mobile
flutter pub get
```

Use one command based on your target:

- Android emulator (AVD):

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

- Android physical device (USB, easiest):

```powershell
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

- Android physical device (same Wi-Fi, no `adb reverse`):

```powershell
flutter run --dart-define=API_BASE_URL=http://<YOUR_PC_LAN_IP>:8000
```

- iOS simulator:

```bash
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

- Web (Chrome):

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

## Optional Cloudinary Defines (for media upload)

Add these to the same `flutter run` command when you need report media upload:

- `--dart-define=CLOUDINARY_CLOUD_NAME=your_cloud`
- `--dart-define=CLOUDINARY_UPLOAD_PRESET=guardian_grid_unsigned`
- `--dart-define=CLOUDINARY_UPLOAD_FOLDER=guardian-grid/hazards`
