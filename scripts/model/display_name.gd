class_name DisplayName
extends RefCounted
## What every surface calls a pane, worked out in this one place: the world's
## plate, the card's title, NEXT, the agent list, NEWS / EVENTS, the OVERVIEW,
## the strategic view, the SPACES rail's windows and the monitor's caption.
## Pure: OfficeProjection names the panes it seats (PaneModel.name) and
## HerdrFleet the panes it hands the state log (StateLog.Sighting.name), both
## through of_pane(), so a pane is called the same everywhere.
##
## The name is the first of: the terminal title (Claude Code writes its task
## summary there) unless it says nothing a provider word would not
## (generic()); the pane's label; its tab's label, unless it is herdr's own
## default (tab_is_default()); the last component of its working directory;
## the name herdr gave its agent; `pane <id>`. Never the provider word alone,
## but for a directory that happens to be called so.
##
## It is remote text: shown, never sent, never part of a command's context or
## an audit, never a key (the pane key and PaneModel.identity_key() are).

## Grapheme clusters a name keeps (TerminalText.clip()); a longer one ends in `…`.
const MAX_CLUSTERS := 80
## A title that is only one of these is a shell's own name, not a task.
const SHELLS: Array[String] = ["sh", "bash", "zsh", "fish", "nu", "pwsh", "tmux", "login", "-zsh", "-bash"]
## What an agent's title leads with before the words: Claude Code's spinner and
## its marks, bullets. U+2800–U+28FF (Braille, other spinners) is checked apart.
const MARKS := "✳✻✽✶✢·•*●○◐◓◑◒⏺"


## herdr's own name for a tab it was never asked to name: its number, or its
## id where it sent no label (HerdrSnapshot.Tab.label); empty says nothing too.
static func tab_is_default(label: String, number: int, tab_id: String) -> bool:
	return label.is_empty() or label == str(number) or label == tab_id


## A tab's label when it is a name somebody gave it, else empty: what the
## name chain reads.
static func tab_named(label: String, number: int, tab_id: String) -> String:
	return "" if tab_is_default(label, number, tab_id) else label


## What a place says for a tab: nothing for the only tab of its workspace
## while herdr still calls it by its number, else its label.
static func tab_shown(label: String, number: int, tab_id: String, tabs_in_workspace: int) -> String:
	return "" if tabs_in_workspace == 1 and tab_is_default(label, number, tab_id) else label


## How many tabs each workspace has, by workspace id: each tab id once, under
## the first workspace it names (the projection's first-wins rule).
static func tab_counts(tabs: Array[HerdrSnapshot.Tab]) -> Dictionary[String, int]:
	var seen: Dictionary[String, bool] = {}
	var counts: Dictionary[String, int] = {}
	for tab in tabs:
		if seen.has(tab.tab_id):
			continue
		seen[tab.tab_id] = true
		counts[tab.workspace_id] = counts.get(tab.workspace_id, 0) + 1
	return counts


## `title` without the spinner and marks it leads with, and without the
## whitespace around it.
static func stripped(title: String) -> String:
	var start := 0
	while start < title.length():
		var code := title.unicode_at(start)
		var mark := code >= 0x2800 and code <= 0x28FF
		if not (mark or MARKS.contains(title[start]) or title[start].strip_edges().is_empty()):
			break
		start += 1
	return title.substr(start).strip_edges()


## The title says nothing about the task: nothing once stripped(), the
## provider (`codex`), the agent's name (`claude-2`), `<provider> code`
## (`Claude Code`), or a shell's own name.
static func generic(title: String, provider: String, agent_name: String) -> bool:
	var words := stripped(title).to_lower()
	if words.is_empty() or SHELLS.has(words):
		return true
	if not provider.is_empty() and (words == provider.to_lower() or words == provider.to_lower() + " code"):
		return true
	return not agent_name.is_empty() and words == agent_name.to_lower()


## The pane's name from its parts (see the class): `tab_named` is already
## empty for herdr's default tab name (tab_named()).
static func of(
	title: String,
	pane_label: String,
	tab_name: String,
	cwd: String,
	agent_name: String,
	pane_id: String,
	provider: String
) -> String:
	var provider_word := provider.to_lower()
	var words := "" if generic(title, provider, agent_name) else stripped(title)
	for candidate: String in [words, pane_label.strip_edges(), tab_name.strip_edges()]:
		if not candidate.is_empty() and candidate.to_lower() != provider_word:
			return TerminalText.clip(candidate, MAX_CLUSTERS)
	# A directory is a directory, whatever it is called.
	var directory := cwd.trim_suffix("/").get_file()
	if not directory.is_empty():
		return TerminalText.clip(directory, MAX_CLUSTERS)
	var named := agent_name.strip_edges()
	if not named.is_empty() and named.to_lower() != provider_word:
		return TerminalText.clip(named, MAX_CLUSTERS)
	return TerminalText.clip("pane " + pane_id, MAX_CLUSTERS)


## The name of snapshot pane `pane` sitting at `tab` (null: the snapshot has no
## such tab).
static func of_pane(pane: HerdrSnapshot.Pane, tab: HerdrSnapshot.Tab) -> String:
	var tab_name := "" if tab == null else tab_named(tab.label, tab.number, tab.tab_id)
	return of(pane.terminal_title_stripped, pane.label, tab_name, pane.cwd, pane.agent_name, pane.pane_id, pane.agent)
