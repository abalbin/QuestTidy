# QuestTidy

Quest log tools and a lighter bag for **World of Warcraft: Forever**.

QuestTidy extends Blizzard's native interface with tracking shortcuts, exact Wowhead quest links, and a review of quest-related bag items. Version **0.2.0** is an early testing build for Forever **1.60.1**, interface **16001**.

## What it does

- **Track all quests** restores tracking across the full quest log, including collapsed zones.
- **Track ready quests only** leaves only quests the client marks ready to turn in tracked. Talk-only quests count when the client marks them ready.
- **Untrack all** removes watches across all zones without abandoning quests.
- **Wowhead comments & tips** adds an action to each native quest menu. The selected URL identifies the exact quest ID, including chain steps with identical names.
- **Review quest items** adds an option to native bag menus. It shows carried quest-related items and offers individual deletion confirmation where quest use is unknown.

QuestTidy does not replace the quest log or bags. It does not change Blizzard's automatic tracking preference. Objective progress may track a quest again.

## Install or update

1. Quit WoW.
2. Place the `QuestTidy` folder inside `_forever_/Interface/AddOns`.
3. Check that the path ends in `Interface/AddOns/QuestTidy/QuestTidy.toc`.
4. If upgrading from the prototype, move `ForeverQuestNotes` out of `Interface/AddOns` so both addons do not load together.
5. Start WoW and enable **QuestTidy** in the AddOns list.

A repository checkout contains the contents of the addon folder. Name its installed folder `QuestTidy`. A packaged ZIP already contains that folder.

## Track quests

Open **Map & Quest Log**, then use **Track quests** above the search field. Choose **Track all quests** or **Track ready quests only**. The separate **Untrack all** button clears existing watches.

Ready-only mode removes nonready watches and adds missing ready quests. Existing ready watches stay tracked. The client may limit tracking or refuse individual changes. QuestTidy reports those failures instead of claiming every quest was tracked. Changes are unavailable during combat. Ready-only mode also honors the client's untracking restrictions.

## Look up current quest comments

Right-click a quest title and choose **Wowhead comments & tips**. Copy the selected URL with **Ctrl+C** or **Command+C**, then paste it into your browser.

WoW addons cannot make arbitrary web requests. QuestTidy does not download comments, open a browser, or copy automatically to the clipboard. The browser URL is the route to current reports. Bundled advice is a dated snapshot and initially covers **The Karnitol Shipwreck**, quest **1456**, reviewed **November 17, 2026**. The low-drop warning describes anecdotes, not a confirmed bug or a measured drop rate. Other quests still receive their exact comments link.

## Review quest items

Open a bag's portrait or settings menu and choose **Review quest items**, or run `/questtidy bags`. The review scans carried bags, including a reagent bag where present. It excludes bank storage and the keyring.

Items the client associates with an active quest are protected. Quest starters are also protected, including starters whose quest was completed before, because they may be repeatable or useful later.

Other discovered quest-related items show **unknown quest use**. This does not establish that they are obsolete. The client does not expose a complete item-to-quest database, so some active, future, repeatable, or shared uses cannot be identified. Ordinary items used by quests may not appear at all.

To discard an item you have reviewed, choose **Delete...** and read the confirmation. Deletion applies to the **entire displayed stack** and is irreversible. There is no bulk deletion. QuestTidy rechecks the item instance, location, stack count, lock, quest status, cursor, and combat before requesting deletion. A moved or changed item requires a fresh review. Missing data disables deletion.

The native deletion API may restrict addon calls. A request is not proof that the item was deleted. Confirm the result in the refreshed bag. If the client refuses, use WoW's ordinary bag controls. No item is deleted merely by opening the review or installing the addon.

## Chat commands

- `/questtidy track` tracks all eligible logged quests.
- `/questtidy ready` leaves only ready-to-turn-in quests tracked.
- `/questtidy untrack` removes current watches.
- `/questtidy bags` opens quest-item review.
- `/questtidy 1456` opens that quest's notes and comments URL.
- `/questtidy help` shows usage.

`/qt` is the short alias. `/fqn` remains an alias for prototype users.

## Test and contribute

Run `luajit tests/run.lua` from the addon directory. The checks execute the actual addon Lua against documented client API test doubles. They do not prove in-game layout, protected-action behavior, or another addon's compatibility. [TESTING.md](TESTING.md) lists the client checks, and [CONTRIBUTING.md](CONTRIBUTING.md) describes how to contribute.

The code targets Blizzard's mirrored Forever UI source at commit `3d8abb1da73acd38e412e24fb3f99454a6392346`, build `1.60.1.70959`. This iteration still requires in-client testing. Enable error dialogs with `/console scriptErrors 1` and include the client build and error text when reporting problems.

## Sources

- [Forever quest menus and tracking](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua).
- [Quest API and ReadyForTurnIn](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua).
- [Native bag menus](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua).
- [Bag item quest metadata](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/ContainerDocumentation.lua).
- [Item identity and deletion APIs](https://github.com/Gethe/wow-ui-source/blob/3d8abb1da73acd38e412e24fb3f99454a6392346/Interface/AddOns/Blizzard_APIDocumentationGenerated/ItemDocumentation.lua).
- [Wowhead tooltips documentation](https://www.wowhead.com/tooltips).
- [Quest 1456 and player comments](https://www.wowhead.com/forever/quest=1456/the-karnitol-shipwreck#comments).

## License

MIT. See [LICENSE](LICENSE). World of Warcraft and Wowhead are owned by their respective owners. QuestTidy is an independent community addon.
