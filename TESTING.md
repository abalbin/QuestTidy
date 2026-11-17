# Test QuestTidy

## Run automated checks

Install LuaJIT and run this command from the repository or addon directory:

```sh
luajit tests/run.lua
```

These checks use the delivered addon code with client API test doubles. They do not establish visual layout or protected-action behavior.

## Check this iteration in Forever

1. Enable QuestTidy, disable or remove Forever Quest Notes, and restart WoW. Run `/console scriptErrors 1`.
2. Open **Map & Quest Log**. Confirm **Track quests** and **Untrack all** fit above the search box. Check the search, quest count, settings, and details view.
3. Untrack your quests, collapse a zone, and enter a search. Choose **Track all quests**. Confirm quests hidden by the collapse and search are also tracked, up to the native limit.
4. Keep a mixture of incomplete, ready, and talk-only quests. Choose **Track ready quests only**. Confirm only quests the client considers ready to turn in remain tracked. A ready talk-only quest must appear even when it has no kill or collection objective.
5. Turn in a quest, accept a new quest, and repeat the tracking actions. Check that the list is fresh. Confirm automatic tracking preferences were not changed.
6. Test the tracking actions during combat and with no quests. Confirm they refuse or report empty results without an error.
7. Right-click quests with different IDs. Confirm **Wowhead comments & tips** retains the correct exact ID. Run `/questtidy 1456` and `/questtidy 1454`; advice for one step must not carry into the other.
8. Open separate bags and combined bags, if available. Check their portrait or settings menus for **Review quest items**. Bank menus should not receive this carried-bag option.
9. Open quest-item review. Confirm active quest items and all quest starters have deletion disabled. A starter for a previously completed quest must remain protected.
10. Confirm unknown items say their use is unknown, rather than claiming they are safe or obsolete. Check links, full stack counts, and bag locations.
11. Select **Delete...** for an item you are willing to lose. Cancel the confirmation. Confirm nothing changes.
12. Open confirmation, then move the stack, split it, or put another identical item instance in that slot. Accept. Confirm deletion is refused and a new review is required.
13. Open confirmation, then enter combat, hold an item on the cursor, or accept a quest that makes the item protected. Confirm acceptance refuses deletion.
14. For one unwanted item, confirm deletion. Verify its actual removal from inventory. If the client blocks the API call, record the error and verify ordinary manual deletion still works. Do not report success based only on a request message.
15. Repeat with missing item data or a locked item. Confirm the addon offers no deletion until complete, current data is available and the item is unlocked.
16. Check Escape, dragging, scrolling, your UI scale, and other installed bag or quest addons.

Use a disposable item for destructive checks. Report the QuestTidy version, `/dump GetBuildInfo()` output, other bag and quest addons, and any Lua error text.
