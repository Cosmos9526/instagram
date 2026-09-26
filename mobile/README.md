# Hashtpa app — PWA (iPhone + Android) and native builds

One Flutter codebase, mobile layout only (portrait, phone width even in a desktop browser), Persian RTL.

## PWA (main target)
The backend Docker image builds the web app and serves it at the same address as the API
(`https://your-domain/`). On the phone:
- **iPhone (Safari):** Share button → **Add to Home Screen**
- **Android (Chrome):** menu ⋮ → **Install app / Add to Home screen**

Only the admin token is asked on first launch; the server address defaults to the page's own address.
`--no-web-resources-cdn` bundles CanvasKit locally, so the app does not depend on Google's CDN.

```bash
flutter build web --release --no-web-resources-cdn   # output: build/web
```

## Native (optional)
```bash
flutter build apk --release    # Android
flutter build ipa              # iOS (needs a Mac + Apple developer account)
```

## Dev
```bash
flutter pub get && flutter test && flutter analyze
```

## Demo build (no server)
```bash
(cd ../backend && python ../tools/make_demo_slides.py ../mobile/build/demo_slides)
flutter build web --release --no-web-resources-cdn --dart-define=DEMO=true
cp -r build/demo_slides build/web/demo
```
Sample data lives in `lib/demo.dart`; nothing is sent anywhere.
