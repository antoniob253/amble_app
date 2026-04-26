# Amble

A walking companion app for older adults — and made gentle.

Native iOS app built in SwiftUI. Counts daily steps from Apple Health, tracks
walks with a Live Activity, surfaces a one-tap SOS, and reads a daily piece of
poetry or philosophy on the Reflect tab. No leaderboards, no shouting wrist
taps, no aggressive fitness energy. Designed end-to-end for an audience that's
tired of fitness apps built for 25-year-olds.

## Stack

- SwiftUI (iOS 18.6+ deployment target)
- HealthKit (read-only step data)
- CoreMotion / CMPedometer (live walk tracking)
- ActivityKit (Live Activity for in-progress walks)
- CoreLocation (one-shot location at SOS time)
- StoreKit 2 via [RevenueCat](https://www.revenuecat.com) for subscription
  management
- [Lottie](https://github.com/airbnb/lottie-ios) for the walking-figure
  animation
- Local-only persistence via UserDefaults; no app servers, no analytics SDKs

## Project layout

```
Amble/
├── AmbleApp.swift           App entry; wires up DI and runs Purchases.configure
├── Theme/                   Sage palette + Fraunces typography
├── Models/                  UserProfile, WalksStore, WalkTracker, ReviewPrompter, …
├── Health/                  HealthStore wrapper around HealthKit
├── Store/                   StoreManager (RevenueCat) + RevenueCatConfig
├── Location/                LocationManager (one-shot, SOS-only)
├── Notifications/           NotificationManager (daily walking reminder)
├── Contacts/                ContactPicker (CNContactPickerViewController bridge)
├── Components/              TabBar, ProgressRing, ScreenShell, etc.
├── Onboarding/              Multi-step onboarding flow
├── Screens/                 Home, Week, Reflect, Settings, Walk, SOS, Call, Paywall
├── Reflections/             reflections.json (public-domain poetry/philosophy)
├── Lottie/                  walker.json (custom 30fps walk-cycle animation)
├── Assets.xcassets          App icons, accent color, onboarding asset
├── PrivacyInfo.xcprivacy    Required Reason API + collected data declaration
├── Info.plist
├── Amble.entitlements       HealthKit capability
└── Amble.storekit           Local StoreKit testing config

AmbleWidget/                 Live Activity (and only Live Activity) for walks
```

## Setup

1. Clone and open `Amble.xcodeproj` in Xcode 26+.
2. Swift Package Manager will resolve dependencies (Lottie, RevenueCat) on
   first open.
3. Set your team in the Amble + AmbleWidgetExtension targets' Signing &
   Capabilities tabs.
4. Build and run on an iOS 18.6+ device or simulator. (HealthKit and CoreMotion
   need a real device for full step / pedometer testing.)

The RevenueCat API key is checked in (`Amble/Store/RevenueCatConfig.swift`) —
it's a public app-specific key (`appl_…`) designed to ship in client binaries.

## Brand voice

- Cream backgrounds, sage accents, Fraunces serif for display, SF for body.
- Larger type defaults than typical fitness apps — older eyes are the audience.
- Anti-shouty: no streaks-broken alerts, no leaderboard pressure, no
  notification spam. The daily walking reminder is the only ping the app
  produces, and it's user-scheduled.
- Privacy-first: everything stays on-device except the anonymous purchase
  receipt that flows through RevenueCat. No accounts, no email, no analytics.

## Status

Pre-launch. App Store metadata is filled in; first submission pending.

---

© 2026 Antonio Baltic
