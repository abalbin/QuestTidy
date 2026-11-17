# Contribute to QuestTidy

Open an issue for a bug, an API change, or a feature proposal. Include the addon version, Forever client build, reproduction steps, expected result, actual result, and relevant Lua error text. Do not include account names, private chat, or other personal data in screenshots.

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
