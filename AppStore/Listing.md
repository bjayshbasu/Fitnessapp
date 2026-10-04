# Workout Genie: App Store listing

Copy each field into App Store Connect → your app → **App Store** tab (version 1.0).
Character limits are Apple's; every field below fits.

## App information

| Field | Value |
|---|---|
| Name (30) | Workout Genie |
| Subtitle (30) | Gym Log, PRs & Macro Tracker |
| Bundle ID | com.bijeshbasu.workoutgenie |
| SKU | workoutgenie-ios |
| Primary category | Health & Fitness |
| Secondary category | Lifestyle |
| Price | Free |

If "Workout Genie" is already taken, try "Workout Genie: Gym Log". The name under the icon stays "Workout Genie" either way.

## Promotional text (170)

Log every set, beat your personal records and let Genie tell you when to add weight. Track calories and macros by scanning barcodes and nutrition labels.

## Description (4000)

Workout Genie is a simple, fast gym log that helps you get stronger, one rep at a time.

LOG WORKOUTS IN SECONDS
• Build routines like Push Day or Leg Day, then tap Start
• Every set starts with what you lifted last time
• Supersets and drop sets built in
• Rest timer with a reminder when it's time for your next set
• See "last time" and your best lifts right inside the workout

LET GENIE PLAN YOUR NEXT STEP
• Hit every rep? Your next workout starts a little heavier
• Bodyweight exercises get an extra rep instead
• You're always in control: change any number

TRACK YOUR PROGRESS
• Weekly charts for volume, workouts, sets and minutes
• Sets by muscle group, so you can spot what you're missing
• Personal records for every exercise, with a trophy the moment you beat one
• Strength trend charts with estimated one-rep max

STAY MOTIVATED
• Weekly workout goal with a streak
• Earn XP for every workout, set and PR
• Level up and unlock 23 achievement badges

NUTRITION, MADE EASY
• Track calories, protein, carbs and fat against your daily goals
• Scan a food barcode to fill in the numbers
• Point the camera at a nutrition label to read it automatically
• Re-add recent foods with one tap
• Get suggested calorie and macro goals from your profile

YOUR DATA, BACKED UP
• Create a free account to back up your workouts, foods and records
• Log in on a new iPhone and everything comes back
• Optionally save workouts to Apple Health
• Export your workout history as a spreadsheet (CSV)
• Delete your account and data at any time, right in the app

Workout Genie is not a medical device. Nutrition values from scans and suggested goals are estimates; check with a professional before making big changes to your diet or training.

## Keywords (100)

gym,workout,tracker,lifting,strength,weightlifting,log,routine,progressive,overload,macros,calories

## URLs

| Field | Value |
|---|---|
| Support URL (required) | The page where you host `PrivacyPolicy.md` works, as long as it shows your contact email |
| Privacy Policy URL (required) | Where you host `PrivacyPolicy.md` |
| Marketing URL | Leave empty |

## Screenshots

Upload the five files in `Screenshots/` (1320 × 2868) in the **6.9" iPhone** slot, in this order:

1. `1-workout.png`: logging a workout
2. `2-stats.png`: stats and charts
3. `3-records.png`: personal records
4. `4-achievements.png`: levels and badges
5. `5-nutrition.png`: calories and macros

## App Review information

| Field | Value |
|---|---|
| Sign-in required | Yes |
| Demo account | Create one in Firebase (Authentication → Users → Add user), e.g. `appreview@` + your domain or a spare email, with a strong password. Log into it once in the app and add a routine so the reviewer sees content. |
| Contact | Your name, phone and email |

Notes for the reviewer (paste as-is):

> Workout Genie is a workout and nutrition log. Use the demo account above to log in.
> To try a workout: Routines tab → open a routine → Start Workout → tick sets → Finish.
> Nutrition tab → + → "Scan barcode" or "Read nutrition label" (uses the camera; the label reader works on device).
> Account deletion: Settings → tap your name → Delete account.
> Apple Health is optional and only used to save finished workouts.

## Age rating

Answer **None** to every content question (no violence, gambling, mature themes, user-generated content shared with others, etc.). Result: **4+**.

## App Privacy (the "nutrition label")

Data used to track you: **No**.

Data linked to the user, all for **App Functionality** only:

| Category | Type |
|---|---|
| Contact Info | Name, Email Address |
| Health & Fitness | Health (sex, birth year, height, weight in the profile), Fitness (workouts) |
| User Content | Photos or Videos (optional profile photo), Other User Content (food diary) |
| Identifiers | User ID |

Not collected: location, contacts, browsing history, purchases, financial info, diagnostics, usage data, advertising data.

These match the privacy manifest in the app (`PrivacyInfo.xcprivacy`). If you add analytics or ads later, both must be updated.

## Export compliance

The build already declares that it uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption = NO`), so App Store Connect won't ask about it.
