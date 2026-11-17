# Contribute to QuestTidy

Use the [bug report form](https://github.com/abalbin/QuestTidy/issues/new?template=bug_report.yml) for problems. For an API change or feature proposal, choose **Open a blank issue** in the [issue chooser](https://github.com/abalbin/QuestTidy/issues/new/choose).

For code changes:

1. Fork the repository and create a branch.
2. Keep Lua compatible with WoW's Lua 5.1 runtime.
3. Check API assumptions against the matching Forever client source rather than Retail or an older Classic branch.
4. Keep native menus and frame behavior intact.
5. Run `luajit tests/run.lua`.
6. Run the relevant checks in [TESTING.md](TESTING.md). State clearly which checks you could not run.
7. Open a pull request that describes the player-visible change and its verification.

For bag changes, preserve per-stack confirmation and identity revalidation. Never equate missing quest data or historical completion with proof that an item is useless. Do not add automatic or bulk deletion.

For quest advice, use numeric quest IDs and a review date. Write your own concise summary, link its source, and distinguish player reports from confirmed changes. Do not commit copied comment collections or claim that bundled notes are live.

## Publish a release

Release tags belong to the repository owner (`abalbin`). Contributors can propose release changes in a pull request.

1. Update `## Version` in `QuestTidy.toc` in the release changes and merge them to `main`.
2. Switch to `main` and run `git pull --ff-only origin main`. Create and push a tag matching the TOC version. For example, for `0.2.3`, run `git tag -a v0.2.3 -m 'QuestTidy 0.2.3'` followed by `git push origin v0.2.3`.
3. Check the **CI and releases** workflow and the resulting GitHub release. The release asset is `QuestTidy-<version>.zip`.

To build the same ZIP locally, run `npm ci --ignore-scripts` followed by `npm run package` with Node.js 20 or newer. The archive in `dist/` contains a single `QuestTidy/` folder with the TOC, its listed files, and the license. Pull request checks build the same package.

When QuestTidy has a CurseForge project, a separate upload job can consume the same verified ZIP. Configure the project ID, Forever game version, and a repository secret for the upload token at that point. [CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api)
