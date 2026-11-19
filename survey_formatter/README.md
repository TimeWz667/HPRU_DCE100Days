# survey_formatter

Turns the choice sets in `Surveys/` into HTML tables for pasting into Qualtrics. Each option cell is one compiled image (icon plus label), so the pasted HTML only holds the table shape.

## Use

1. Compile the images after any change to `Surveys/`, `def/` or `Icons/`, then commit and push `dist/`:

   ```bash
   cd survey_formatter
   npm install
   node build/compile.mjs
   ```

   Options: `--design CHD --block 1 --q 1` compile a subset. Designs on hold (`hold: true` in `shared.js`) are skipped.

2. Run the app from the repo root and open <http://localhost:8000/survey_formatter/>:

   ```bash
   python -m http.server 8000
   ```

3. Pick a survey version, a block tab, then click a question button. The HTML table for that block and question is copied to the clipboard and the button turns green. Paste it into the question's HTML view in Qualtrics.

The copied HTML has the selected block number in the image URLs. Tick the checkbox to use `${e://Field/block}` instead (needs embedded data `block` in the Survey Flow).

## Details

- Row order follows `def/attributes_{chd,old}.json` (VACCINE last). Questions are numbered by ascending set number within a block.
- Image paths: `dist/<design>/b<block>/q<NN>/a<1|2>_<ATTR>.png`. `dist/manifest.json` lists each image's label and icon.
- Images are served from jsDelivr, from the `release` branch (`IMAGE_BASE` in `app.js`). After compiling: commit and push `main`, then run `npm run release` to publish them. Override locally with `?base=/survey_formatter/dist/`.
- The first column font scales with screen width.
- Alt text is `<attribute>: <label>` and is fixed when pasted. Changing an image's file never needs a re-paste (the URL stays the same), but changing a label does.

## Keeping the pasted HTML up to date

After you paste questions into Qualtrics, record the commit: `npm run changed -- --mark` (then commit `last_pasted.txt`). After later changes, `npm run changed` lists the questions whose alt text changed, so you re-paste only those. It also says which questions only had their images updated (no re-paste; run `npm run release`).

Hosting for the pilot and for full data collection: see [HOSTING.md](HOSTING.md).
