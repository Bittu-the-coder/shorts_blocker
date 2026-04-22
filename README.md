# Focus Guard

Focus Guard is an Android-first Flutter app built to reduce doomscrolling and make phone usage more intentional. It detects short-form video surfaces like YouTube Shorts and Reels, tracks how your time is spent, and lets you define your own rules for what counts as productive versus wasted time.

## Highlights

- Blocks Shorts and Reels style content in supported apps and browsers
- Tracks usage as `time waste`, `productive`, or `neutral`
- Lets you create custom rules for apps and browsers
- Supports browser-based detection for Chrome, Firefox, Edge, Brave, Samsung Internet, Opera, and Vivaldi
- Includes X/Twitter short-video and status-page heuristics
- Stores rules and stats locally on-device

## Why This Exists

Most blockers are either too strict or too generic. Focus Guard is designed to be flexible:

- You decide which apps are distractions
- You decide which apps are for learning or work
- Shorts blocking can be enabled only where you want it
- Usage is tracked so you can see the tradeoff between wasted time and productive time

## Privacy And Safety

Focus Guard does not upload your personal data to any server.

- All rules and usage stats are stored locally on your device
- No account is required
- No cloud sync is used
- No personal browsing history is sent anywhere by the app

This means the app is designed to be safe to install for personal use, with data staying on-device.

## Tech Stack

- Flutter
- Android AccessibilityService
- SharedPreferences

## Release Description

Focus Guard helps reduce short-form video addiction by blocking Shorts and Reels in supported apps and browsers, while also tracking whether your phone time is productive, neutral, or wasted. It includes customizable per-app rules, browser heuristics, and an on-device dashboard for daily focus tracking.
