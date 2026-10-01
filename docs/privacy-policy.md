# Privacy Policy: FATNAG

**Publisher:** Human Analog Limited  
**App:** FATNAG (iOS)  
**Effective:** for App Store builds 2.51.0+

Host this page at the URL set in `ScaleLegal.privacyPolicyURL` (default `https://humananalog.github.io/fatnag/privacy`) and paste that URL into App Store Connect → App Privacy / App Information.

## What stays on your iPhone

- Scale readings, calibration, profile, Coach memory, personas, and preferences are stored on-device (`UserDefaults` / local files).
- Confirmed weigh-ins write weight, BMI, body fat %, and lean body mass to **Apple Health** when you tap Confirm. Manual entries are marked user-entered in Health.
- Health reads (weight, fat %, HR, RHR, HRV, sleep, steps, energy, workouts, and related fitness signals) stay on-device for charts, digests, and local algorithms unless you opt into Coach.

## Optional Coach (Grok)

- Off by default. After you allow Coach requests, chat text and a fitness digest may be sent to our Cloudflare Worker, which calls xAI. We do not sell this data.
- You can revoke consent anytime in Settings. On-device Apple Intelligence (when available) can polish notifications and private digests without leaving the phone. On iPhones without Apple Intelligence, FATNAG may download a private ~470 MB on-device polish model (Qwen2.5 0.5B) that runs only on your iPhone; Apple Intelligence phones never receive that download.

## Notifications

- Local only. Used for Coach reminders, trend / mini-goal nudges, and Watch / sleep-HR signals you enable. No marketing spam.

## Tracking

- No advertising identifier, no analytics SDKs, no cross-app tracking.

## Contact

- Human Analog Limited: **privacy@humananalog.ai**
- Hosting the public policy: `TheScale/docs/operations/legal-url-hosting.md`
- Target URL: `https://humananalog.github.io/fatnag/privacy` (`ScaleLegal.privacyPolicyURL`)

## Medical

This app is not a medical device. Coaching is fitness guidance only. The medical disclaimer appears once in onboarding and under Settings → Legal.

## App Store Connect nutrition labels (suggested)

| Data | Linked to identity | Used for tracking | Purpose |
|------|--------------------|-------------------|---------|
| Health & Fitness | No | No | App Functionality |
| Other User Content (Coach chat, when consented) | No | No | App Functionality |

Export compliance: HTTPS only → `ITSAppUsesNonExemptEncryption` = **NO** in the binary.
