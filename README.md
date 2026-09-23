# Pantry Ping

A simple iOS app that tells you what food you have, where it is, how much is left, and what to use next.

**Add food → Store it → Track freshness → Get pinged → Use it / Cook it / Freeze it / Toss it**

Built with Swift, SwiftUI, and SwiftData. Everything stays on the device: there are no accounts, no servers, and no third-party libraries.

## Running it

1. Open `Pantry Ping/Pantry Ping.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator, such as iPhone 17, from the device menu at the top.
3. Press **⌘R**.
4. On the empty screen, tap **Try Sample Groceries** to explore with demo data (groceries, a part-used granola box, a prepared meal, and a shopping list), or tap **+** to add your own.

To run the tests, press **⌘U**. The UI tests take several minutes. If the simulator struggles, run them from Terminal with `-parallel-testing-enabled NO`.

## The data model

These four ideas are kept separate:

| Concept | Type | What it holds |
| --- | --- | --- |
| **Saved product** | `Product` | Reusable details for a food, e.g. "Quaker Protein Granola": category, photo, serving size and unit, servings per package, and optional calories, carbs, protein, and fat per serving. |
| **Purchased package** | `GroceryItem` | One box you bought: purchase date, price, package size, amount remaining, storage location, food state, and use-by date. **Buying again creates a new package** and never touches older ones. |
| **Usage entry** | `UsageEntry` | An amount taken from a package or meal, with a date and a reason: *Ate*, *Used in meal prep*, or *Other use*. **Only "Ate" counts toward the daily food log.** |
| **Prepared meal** | `PreparedMeal` + `MealIngredient` | A meal-prep batch with its ingredients, portions and/or cooked weight, storage, dates, and optional nutrition. |

There are also two supporting types:
- `ShoppingItem`: the shopping list.
- `FoodEvent`: a package's dated history, such as bought, opened, frozen, moved, or finished.

## What works

| Area | Features |
| --- | --- |
| **Kitchen** | Groceries grouped by urgency: **Expired**, **Needs Attention**, **Use Soon**, and **Your Food**. Each row shows how much is left ("279 g · 4.5 servings"). Also has an All / Fridge / Freezer / Pantry filter and search. |
| **Kitchen swipe actions** | Swipe right for **Use Some** or **Finished**. Swipe left for **Threw Away**, and for **Still Have It** on expired items. |
| **Adding groceries** | **+** opens your saved products for **Buy Again**, or **New Product** for something new. A new product asks for its name, an optional photo, and optional serving and nutrition details, together with the first package's size, price, dates, and storage. **Buy Again** only asks for the package details and reuses the product's name, photo, serving size, and nutrition. |
| **Photos** | Pick from your library or take one with the camera (on a real phone). The photo is saved once, with the product. |
| **Use Some** | Enter the amount as servings or as a measured amount (g, kg, oz, lb, ml, cups, tbsp, pieces). You can't take more than what's left. A preview shows what will remain and the nutrition for that amount. **Use All** takes exactly what's left. When a product has several open packages, the one expiring first is suggested, but you can pick any of them. |
| **Finished / Threw Away** | The item leaves the kitchen and stops getting reminders. Its history is kept, and you can restore it. |
| **Food states** | Open, Cook, Freeze, and Thaw. Each is recorded in the package's history, and the original package date is kept. |
| **Suggested timelines** | A few general-guidance suggestions, **labeled "suggested" everywhere**: in rows, in the detail view, and in reminders. See the food-safety notes below. |
| **Meals tab** | Create a meal-prep batch from groceries in your kitchen; this takes the right amounts out of the right packages. You can also add untracked ingredients or enter a meal by hand without macros. Set portions and/or cooked weight. Nutrition is shown per batch, per portion, and per 100 g when there's enough data. **Eat a Portion** reduces what's left and logs what you ate. |
| **Log tab** | Your daily food log, with day-by-day navigation. Totals mark missing values ("520+ kcal (1 not entered)") instead of counting them as zero. Swipe to undo an entry, which puts the amount back where it came from. |
| **Shopping tab** | Quick-add items; names are matched to saved products. **Buy** opens the purchase form, and the item leaves the list once it's bought. |
| **History tab** | **Purchases** groups everything by the day you bought it, with package sizes, prices, and daily totals. **Finished** lists items you finished or threw away, with counts and restore. |
| **Saved Products** | Opens from the Kitchen **⋯** menu. Browse, edit, buy again, or add to the shopping list. Each product shows its packages, past and present. |
| **Reminders** | One notification a day at 9 AM for groceries and meals with 3, 2, 1, or 0 days left. Settings are in the Kitchen **⋯** menu. |

## Quantity rules

- **Amounts are stored as whole numbers of thousandths** of a base unit: grams, milliliters, pieces, servings, or portions. For example, 310 g is stored as `310000`, so repeated partial uses never pile up rounding errors. Numbers are rounded only for display.
- **Conversions use only fixed unit definitions** (g↔oz↔lb, ml↔cups↔tbsp) **or the product's own serving size.** Weight and volume are never converted into each other, because that would need the food's density. If there's no known conversion, the app says so and offers the units it can use.
- **Example:** 5 servings × 62 g = **310 g**. Using 31 g leaves **279 g**, which is **4.5 servings**.
- You can't log more than what remains, inventory can't go negative, and fractional servings work (for example, 0.25 servings = 15.5 g).

## Food-safety notes

- Pantry Ping mostly relies on **dates you enter**. A food-safety reviewer approved the small set of suggestions it offers. They come from USDA FSIS, use the conservative end of each range, and appear only when you tap **Use Suggestion**:
  - **Cooked leftovers:** 3 days in the fridge (USDA: 3–4 days).
  - **Meal prep stored in the fridge:** 3 days from the prep date.
  - **Thawed meat and seafood:** 1 day (USDA: 1–2 days for ground meat, poultry, and seafood). The app also advises cooking right away if the food was thawed in cold water or the microwave.
- **Freezing gets no date.** Food kept frozen the whole time stays safe, but its quality declines.
- **Suggested dates never say "Expired".** They read "3 days left · suggested" or "Past suggested date", and always show a caveat: *"General guidance for food kept at 40°F (4°C) or below, not a safety guarantee."* Editing a suggested date makes it your own date.

## Decisions and assumptions

- **SwiftData with versioned schemas.**
  - `SchemaV1` is the original frozen shape. `SchemaV2` is the current one.
  - `PantryPingMigrationPlan` upgrades old data: each old item becomes a package counted in pieces, items with the same name share one saved product, and a "Bought" history line is added.
  - A unit test opens a real V1 database file to check this, and it was also checked on an existing simulator install.
- **Every stored property has a default**, relationships are optional, and enums are saved as raw strings that must never be renamed.
- **The package keeps its own copy of the product name**, so the food log and history still read correctly if a product is later deleted.
- **Usage entries save the nutrition for the amount at the time it was logged**, so editing a product later doesn't rewrite past logs.
- **"Finished" reuses the V1 status value `used`** to stay compatible with existing data.
- **Money is stored as `Decimal`**, and the currency follows the device's region.
- **Meal nutrition is only shown for values every ingredient has.** Untracked ingredients mark the total as incomplete.
- **Deleting a meal doesn't put its ingredients back.** Undoing an individual food-log entry does restore the amount.

## Not built yet

These are deferred, following the roadmap:

- Onboarding presets
- Configurable reminder time
- Barcode, receipt, or nutrition-label scanning
- Recipe suggestions
- Spending insights and roommate cost-splitting
- Cloud sync
- A verified food-storage database

## Development notes

- **UI tests launch with `-uiTesting`**, which uses an in-memory database, and with `-remindersEnabled NO`.
- **After the first App Store release**, any model change needs a `SchemaV3` and a new migration stage.
- **Food-safety wording** lives in `Models/FoodState.swift` and `Logic/StorageGuidance.swift`.
