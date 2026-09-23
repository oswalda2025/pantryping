# Pantry Ping

A simple iOS app that tells you what food you have, where it is, and what to use next.

**Add food → Store it → Track freshness → Get pinged → Use it / Freeze it / Toss it**

Built with Swift, SwiftUI, and SwiftData. Everything stays on the device: there are no accounts, no servers, and no third-party libraries.

## Running it

1. Open `Pantry Ping/Pantry Ping.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator, such as iPhone 17, from the device menu at the top.
3. Press **⌘R**.
4. On the empty screen, tap **Try Sample Groceries** to explore with demo data, or **Add Grocery** to add your own.

To run the tests, press **⌘U**. The UI tests take a few minutes.

## What works

| Area | Features |
| --- | --- |
| **Kitchen (home)** | A greeting and pantry status line. Groceries are grouped into **Expired**, **Needs Attention** (0–1 days left), **Use Soon** (2–3 days), and **Your Food**, with the most urgent first. Includes an All / Fridge / Freezer / Pantry filter, search, and empty states. |
| **Add / edit** | Only the name is required. A use-by date is optional, with quick picks (Today, +3 days, +1 week, +2 weeks). Also stores location (the last one you used is remembered), category, quantity, purchase date, and notes. |
| **Swipe actions** | Swipe right for **Used**. Swipe left for **Thrown Away**, plus **Still Have It** on expired items. |
| **Item detail** | Status, all dates, Used / Thrown Away, food-state changes, edit, and delete (with confirmation). |
| **Food states** | **Open, Cook, Freeze, Thaw**. Each change records its date and moves the item (Freeze → Freezer, Thaw/Cook → Fridge). A short sheet shows general guidance and lets you set a new use-by date. |
| **History** | Used and thrown-away items with counts. Swipe to restore or permanently delete. |
| **Reminders** | One local notification a day at 9 AM when items have 3, 2, 1, or 0 days left. Can be turned on or off in Settings. Permission is requested the first time a dated item exists. |
| **Settings** | Reminders toggle, "Add sample groceries", and the food-safety disclaimer. |
| **Accessibility** | Urgency is always shown with text *and* an icon, never color alone. Rows read as one sentence in VoiceOver ("Milk, Fridge, Expires tomorrow"). Dynamic Type works because only system fonts are used. |

## Project structure

```
Pantry Ping/Pantry Ping/
├── Pantry_PingApp.swift          App entry; creates the SwiftData database
├── ContentView.swift             Tabs, the app-wide "now" clock, reminder scheduling
├── Models/                       GroceryItem (@Model, versioned schema) + enums
├── Logic/                        Urgency, labels, sorting, and food-state rules (pure, tested)
├── Notifications/                Reminder planning (pure, tested) and scheduling
├── Views/                        Home, rows, form, detail, date sheet, History, Settings
└── Preview/SampleData.swift      Demo groceries for previews and the sample button
Pantry Ping/Pantry PingTests/     Unit tests (Swift Testing)
Pantry Ping/Pantry PingUITests/   End-to-end flow tests (XCTest)
```

## Decisions and assumptions

These choices were made deliberately. Changing some of them later is expensive.

- **SwiftData with a versioned schema (`SchemaV1`)** and an empty migration plan from day one. Every stored property has a default value, so new fields can be added without crashing, and iCloud sync stays possible later.
- **Enums are saved as raw strings** (`"fridge"`, `"meatSeafood"`). **These raw values must never be renamed.** Unknown values fall back to a safe default instead of crashing.
- **Used or thrown-away items are never deleted**, only marked, so History and future food-waste stats have data. Delete exists for mistakes.
- **"Expired" is always calculated, never stored.** It comes from the date and the current day.
- **Dates are calendar days stored at 12:00 noon local time.** Days left are counted in calendar days, so the result survives midnight, daylight-saving changes, and time-zone trips of up to about ±11 hours.
- **Two expiration dates:**
  - `originalExpirationDate` is what you entered when adding the item. Food-state changes never touch it.
  - `expirationDate` is the current use-by date the countdown uses.
- **No invented food-safety durations.** Pantry Ping only uses dates *you* enter:
  - Cooking, freezing, or thawing clears the old date unless you set a new one.
  - Opening keeps the package date, with a note that it may no longer apply.
  - Items without a date show what we do know, such as "Frozen 4 days ago", with a gentle "Add a use-by date?" nudge for opened, cooked, and thawed food.
  - A food-safety reviewer checked all the guidance wording.
- **Refreezing thawed food is allowed**, with a caution that it's only appropriate for fridge-thawed food.
- **"Expires" / "Expired" wording** follows the product spec. Because many package dates are quality dates rather than safety dates, the "Still have it?" prompt and the disclaimer make that clear.
- **Reminders are one digest per day**, not one per item. This avoids spamming you and stays under iOS's 64-pending-notification limit.
- **The app display name is "Pantry Ping"**, so Xcode's module name is `Pantry_Ping`.
- **Quantity is a whole number from 1 to 99.** Units such as lb or g are not added yet.

## Not built yet

These features are intentionally deferred, following the roadmap in the project spec:

- Onboarding presets (Student / Solo / Household)
- Configurable reminder time and days
- Barcode, receipt, or nutrition-label scanning
- Image recognition
- Recipe suggestions ("What can I make with what's expiring?")
- Nutrition mode
- Prices, spending, and roommate cost-splitting
- Cloud sync
- A verified food-storage database. Until one exists, all dates come from the user.

## Development notes

- **If the model changes before the first App Store release**, delete the app from the simulator (long-press the icon → Remove App) so it starts with a fresh database. After release, schema changes must go through a new `SchemaV2` and a migration stage instead.
- **UI tests launch the app with `-uiTesting`**, which uses an in-memory database, and with `-remindersEnabled NO`, which prevents the notification permission alert.
- **Food-safety guidance text** lives in [`Models/FoodState.swift`](Pantry%20Ping/Pantry%20Ping/Models/FoodState.swift).
