# App Store marketing assets

Generated on an **iPhone 17 Pro Max** (6.9" — the size App Store Connect requires;
it also satisfies the 6.7"/6.5" slots).

- `screenshots/6.9/` — five 1320×2868 PNGs (Home, Cards, Budget, Analytics, Activity)
- `previews/preview_6.9_1320x2868.mp4` — ~16s App Preview (H.264, 30fps)

## How they were made (reproducible)

Both use throwaway launch hooks that are **no-ops in a normal/shipped launch**:

- `DEMO_SEED=1` — seeds realistic demo cards + current-month transactions
  (`BudgetTracker/Helpers/DemoSeed.swift`).
- `UI_SCREEN=<home|cards|budget|analytics|activity>` — opens the app directly on a
  screen (`RootView` / `BudgetView`), for deterministic per-screen screenshots.
- `UI_DEMO_TOUR=1` — auto-drives the app through its screens (`RootView.runDemoTour`),
  for the preview recording.

Screenshots (deterministic, one clean launch per screen):

```sh
UDID=<iPhone 17 Pro Max udid>; BID=com.github.jaramah.BudgetTracker
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
for s in home cards budget analytics activity; do
  xcrun simctl terminate "$UDID" "$BID"
  SIMCTL_CHILD_DEMO_SEED=1 SIMCTL_CHILD_UI_SCREEN=$s xcrun simctl launch "$UDID" "$BID"
  sleep 3; xcrun simctl io "$UDID" screenshot "$s.png"
done
```

App Preview:

```sh
xcrun simctl io "$UDID" recordVideo --codec h264 --force raw.mov &
SIMCTL_CHILD_DEMO_SEED=1 SIMCTL_CHILD_UI_DEMO_TOUR=1 xcrun simctl launch "$UDID" "$BID"
sleep 30; kill -INT %1
# trim off the launch, re-encode to constant 30fps:
ffmpeg -ss 3 -i raw.mov -r 30 -c:v libx264 -pix_fmt yuv420p -crf 20 \
  -movflags +faststart -an previews/preview_6.9_1320x2868.mp4
```
