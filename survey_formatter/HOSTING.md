# Image hosting plan

## Now: jsDelivr serving the `release` branch

Images are committed under `survey_formatter/dist/` and served through the jsDelivr CDN from the `release` branch:
`https://cdn.jsdelivr.net/gh/TimeWz667/HPRU_DCE100Days@release/survey_formatter/dist/` (`IMAGE_BASE` in `app.js`).

The pasted Qualtrics HTML always uses `@release`, so it never needs re-pasting when images change.

- Work on `main` as usual. Nothing reaches respondents yet.
- To publish an approved version: commit and push `main`, then run `npm run release` in `survey_formatter/`. It moves `release` to the current `main` (fast-forward only) and purges the changed images from the jsDelivr cache. jsDelivr caches branch files (about 12 hours, check the jsDelivr docs), which is why the purge matters.
- To freeze for fielding: stop publishing, add a GitHub branch protection rule on `release` that blocks pushes, tag the frozen commit (for example `pilot-v1`) and record its commit hash in the study records.
- A design change after launch is a new study version: use a new branch (for example `release-v2`) and paste again.

## Alternative to try: iframe version

Instead of pasting a table of images, paste a one-line `<iframe>` that loads `q.html`, which builds the question from the CSV, attribute definitions and icons in the repo (real text, no compiled images, no alt text to keep in sync). The existing image and icon-plus-text outputs are unchanged.

1. Serve `q.html` from GitHub Pages. jsDelivr does not serve HTML pages, so Pages is needed:
   GitHub repo **Settings -> Pages -> Build and deployment -> Source: Deploy from a branch**, branch `release` (or `main` while testing), folder `/ (root)`.
2. In the app, tick **iframe snippet (needs GitHub Pages)**, pick the version, block and question, and paste the copied snippet into the Qualtrics HTML view:

   ```html
   <iframe src="https://timewz667.github.io/HPRU_DCE100Days/survey_formatter/q.html?design=CHD&amp;block=3&amp;q=7"
           title="Choice question 7" style="width: 100%; height: min(150vw, 880px); border: 0;"></iframe>
   ```

3. Publishing works as before: `npm run release` moves `release`, and Pages redeploys it (about a minute; the CDN may cache for a few minutes more).

Notes:
- The iframe height is a fixed rule (150% of the page width, at most 880 px), measured from `q.html` at 320-700 px wide. It leaves some blank space under the table on wider screens. `q.html` also posts its height to the parent page, which only helps if Qualtrics custom JavaScript is allowed.
- Your Qualtrics account must allow iframes in questions.
- The block number comes from the URL (a literal number, or the `${e://Field/block}` pipe with the checkbox ticked).
- Test locally with `python -m http.server 8000` and open `http://localhost:8000/survey_formatter/q.html?design=CHD&block=1&q=1`, or start the app with `?pages=/`.

## Full data collection: move to the Qualtrics graphics library

Do this once the design is frozen, because the URLs cannot be edited after upload.

### Why
- The survey no longer depends on GitHub or a third-party CDN being up.
- Best reliability for respondents.

### What changes
- Qualtrics image URLs look like
  `https://<brand>.<datacenter>.qualtrics.com/ControlPanel/Graphic.php?IM=IM_xxxxxxxxxxxxxxx`
  (confirm the exact form by uploading one image and copying its URL).
- The ID is random: no path, no block number in the URL. The copied HTML must look up each cell's ID instead of building a path.
- Re-uploading creates new IDs, so changed images mean re-pasting the HTML. This is why it is only for the frozen design.

### Scale
An image depends only on its icon and label, so there are **22 unique images** across CHD and OLD (16 CHD, 17 OLD), not the 1,152 positional files. Upload those 22.

### Steps
1. Freeze the design: choice sets (`Surveys/`), labels (`def/`), icons (`Icons/`), wording. Tag the repo (e.g. `pilot-v1`).
2. Recompile (`node build/compile.mjs`) and list the unique images (icon + label) from `dist/manifest.json`.
3. Upload the 22 images to the Qualtrics Library, then copy each image's ID into a lookup file (for example `survey_formatter/qualtrics_ids.json`, mapping `icon|label` to `IM_…`). Alternative: script the upload with the Qualtrics API, which needs an API token from the user.
4. Add a mode to the copy button in `app.js` that writes the Qualtrics URL for each cell from the lookup file, instead of the `IMAGE_BASE` path.
5. Paste the HTML for all questions, per block, into Qualtrics.
6. Check one question per block and design in Qualtrics Preview, on a phone as well.

### Fallback
If the library is not an option, keep serving from jsDelivr, frozen as above.
