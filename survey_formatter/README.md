# survey_formatter

Web app that turns the choice sets in `Surveys/` into HTML tables (layout from `template.txt`) for pasting into a survey platform.

1. Pick a survey version.
2. Pick a block tab.
3. Click a question button: the raw HTML table is copied to the clipboard and the button turns green.

## Run

From the repo root:

```bash
python -m http.server 8000
```

Then open <http://localhost:8000/survey_formatter/>.

Row order follows `def/attributes_{chd,old}.json` (VACCINE last).

Icons in the output point to the GitHub raw URLs (`ICON_BASE` in `app.js`), so new icons must be pushed to `main` to show in the survey.
