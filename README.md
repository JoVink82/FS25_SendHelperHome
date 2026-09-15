# FS25 Send Helper Home

*(Nederlandse uitleg staat onder de Engelse versie.)*

A Farming Simulator 25 mod that automatically sends the AI helper (hired worker) home to a spot you choose, as soon as it has fully finished the field work.

## How to use

1. Drive (or walk) to the spot on your farm where helpers should park, then press **Ctrl+L**.
2. From now on, whenever a hired helper finishes a field completely, it will automatically drive itself to that spot.
3. Press **Alt+L** to remove the saved spot for your farm.

Both keys are rebindable in *Options > Controls*, and the same actions are also available as console commands `shhSetHome` / `shhClearHome`.

> The helper only drives home when the field work is fully completed — not when it stops early due to an empty tank, no fuel, or because you stopped it yourself.

The mod is fully translated: English, Dutch (Nederlands) and German (Deutsch).

## Installation

1. Download or clone this repository.
2. Copy the entire `FS25_SendHelperHome` folder into your FS25 mods folder:
   `Documents\My Games\FarmingSimulator2025\Mods\`
3. Enable the mod in the in-game mod selection screen when starting or loading a savegame.

## Project structure

- `modDesc.xml` — mod manifest (metadata, keybindings, references to the localization files).
- `scripts/SendHelperHome.lua` — the mod logic (AI job detection, sending the helper home, saving/loading the home point).
- `translations/l10n_en.xml`, `l10n_nl.xml`, `l10n_de.xml` — the English, Dutch and German translations.
- `NOTES.md` — development notes documenting how the mod hooks into FS25's AI job system.

## Requirements

- Farming Simulator 25.

---

## Nederlands

Een Farming Simulator 25 mod die de ingehuurde AI-helper automatisch naar een zelf gekozen plek op je erf stuurt, zodra hij het veldwerk volledig heeft afgerond.

### Gebruik

1. Rijd (of loop) naar de plek op je erf waar helpers moeten parkeren, en druk dan op **Ctrl+L**.
2. Vanaf nu rijdt een ingehuurde helper automatisch naar die plek zodra hij een veld volledig heeft afgewerkt.
3. Druk op **Alt+L** om de opgeslagen plek voor jouw boerderij te wissen.

Beide toetsen zijn te wijzigen via *Opties > Besturing*, en dezelfde acties zijn ook beschikbaar als consolecommando's `shhSetHome` / `shhClearHome`.

> Let op: de helper rijdt alleen naar huis als het veldwerk echt helemaal klaar is (niet als hij eerder stopt door een lege tank, brandstof, of omdat je hem zelf stopzet).

### Installatie

1. Download of clone deze repository.
2. Kopieer de hele map `FS25_SendHelperHome` naar je FS25 mods-map:
   `Documents\My Games\FarmingSimulator2025\Mods\`
3. Vink de mod aan in het mod-selectiescherm bij het starten of laden van een save game.
