# Hashtpa mobile (Android + iOS only)

Persian RTL panel for the Hashtpa backend. Portrait phones only; no desktop/web targets.

Screens: server connect · daily posts (auto-refresh while building) · generate (type, single/carousel,
video length 10–40s, topic) · post detail (slides, caption copy, share to Instagram, edit text, approve/
reject/regenerate) · video prompt package (copy each clip prompt in order) · business profile + weekly plan.

```bash
flutter pub get
flutter run                 # on a connected phone/emulator
flutter build apk --release # Android APK -> build/app/outputs/flutter-apk/app-release.apk
flutter test && flutter analyze
```
First launch asks for the server URL (e.g. `https://hashtpa.example.com`) and `ADMIN_TOKEN`.
