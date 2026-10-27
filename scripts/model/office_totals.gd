class_name OfficeTotals
extends RefCounted
## What the top bar's right end says about the fleet, made once per refresh
## from the frame (OfficeTotals.of()): how many machines answer, how many panes
## the live ones carry (`13 panes`), and each machine for the status line's
## hover (machines_tip()). Who needs you is the portrait strip's
## (PortraitBarModel).
##
## Only a machine whose snapshot is current counts (BuildingModel.stale): a lost
## connection carries no panes (AGENTS.md invariant 4).

## Written for a space whose label is empty.
const UNNAMED_SPACE := "?"
## How a machine's MachineLiveness.State reads in the hover.
const MACHINE_WORDS: Dictionary[MachineLiveness.State, String] = {
	MachineLiveness.State.LIVE: "LIVE",
	MachineLiveness.State.CONNECTING: "CONNECTING",
	MachineLiveness.State.OFFLINE: "OFFLINE",
}


## One machine in the status line's hover. Filled by the office from the fleet:
## the model never reaches a connection (AGENTS.md invariant 1).
class MachineRow:
	extends RefCounted
	## Its machine key (HerdrFleet's): what its chip in the top bar is kept by and picks.
	var key := ""
	var label := ""
	var state := MachineLiveness.State.OFFLINE
	## Unix time the machine's client last read a snapshot or applied a status
	## event (HerdrFleet.heard_since()); −1 when it never has.
	var heard_since := -1.0
	## The SSH forward's last complaint; empty for none.
	var error := ""


## Machines answering now, and machines in the fleet.
var machines_live := 0
var machines_total := 0
## Panes the live snapshots carry, shells and unseated panes included.
var panes := 0
## Every machine in the fleet, Local first, as handed in.
var machine_rows: Array[MachineRow] = []


## The counts of `frame`'s live machines, with `machines` for the status
## line's hover (the office's, from the fleet).
static func of(frame: OfficeFrame, machines: Array[MachineRow]) -> OfficeTotals:
	var totals := OfficeTotals.new()
	totals.machine_rows = machines
	totals.machines_total = frame.buildings.size()
	for building in frame.buildings:
		if building.stale:
			continue
		totals.machines_live += 1
		totals.panes += building.panes
	return totals


## The status line's hover at `now` (unix seconds): each machine, how it
## answers and how long ago it was last heard from, and its forward's last
## complaint; a line each.
static func machines_tip(machines: Array[MachineRow], now: float) -> String:
	var lines := PackedStringArray()
	for machine in machines:
		lines.append(machine_line(machine, now))
	return "\n".join(lines)


## One machine's line of machines_tip(): `Local · LIVE · last snapshot 3s ago`.
static func machine_line(machine: MachineRow, now: float) -> String:
	var heard := "never" if machine.heard_since < 0.0 else _ago(now - machine.heard_since)
	var line := "%s · %s · last snapshot %s" % [machine.label, MACHINE_WORDS[machine.state], heard]
	if not machine.error.is_empty():
		line += " · " + machine.error
	return line


## `45s ago`; OfficeAttention.format_duration() words it.
static func _ago(seconds: float) -> String:
	return OfficeAttention.format_duration(maxf(seconds, 0.0)) + " ago"
