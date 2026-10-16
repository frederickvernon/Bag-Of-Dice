class_name ProConfig
extends RefCounted
## Every Free / Pro limit and product setting, in one place.

## One-time, non-consumable unlock.
const PRODUCT_PRO: String = "bag_of_dice_pro"
## Saved sets a free user can create (example sets count; grandfathered pre-Pro sets don't lock).
const FREE_SET_LIMIT: int = 3
## Palette ids (see DicePalette) free users can choose; Pro adds the rest.
const FREE_COLOURS: Array[String] = ["ivory", "black", "red", "blue", "green"]
const PRO_COLOURS: Array[String] = ["orange", "yellow", "teal", "purple", "pink"]
## Price shown by the fake store only; the real store supplies localised text.
const FAKE_PRICE_TEXT: String = "$3.99"
const FAKE_PRODUCT_TITLE: String = "Bag of Dice Pro"
