# QuestTidy agent instructions

- Keep addon code compatible with WoW's Lua 5.1 runtime. Verify game API assumptions against the Forever client and preserve Blizzard's menus, quest log, and bag behavior.
- Use Node.js and npm for repo tooling, packaging, and release scripts. Do not add or use Python for repo automation. Commit the npm lockfile when dependencies change.
- Keep bag actions tied to the selected stack. Recheck its identity and current quest use at confirmation. Protect active quest items and quest starters. Treat missing data as unknown and keep deletion individual and confirmed.
- Key quest advice by numeric quest ID. Date bundled notes, link their sources, and distinguish player reports from confirmed facts.
- Run `luajit tests/run.lua` for addon changes. For packaging or CI changes, run `npm ci --ignore-scripts` and `npm run package`. Use [TESTING.md](TESTING.md) for in-game checks and report which checks you actually ran.
- Make changes on a branch and open a pull request to `main`. Keep the required **Test and package** check intact. Read the release steps in [CONTRIBUTING.md](CONTRIBUTING.md) before changing release tooling or versioning. Only create release tags or publish when the maintainer requests a release.
