# Skills

Client skill files that ship with eda-agent. `.claude/` is gitignored (it
holds local client state), so the canonical source lives here and you copy
what you need into your client.

## altium-bridge (this fork)

Working on a live Altium project through the restricted, checked bridge of this fork: operator-selected
project, reads that refuse rather than guess, writes that go preview, tick, apply, read-back and never save.
See [altium-bridge/SKILL.md](altium-bridge/SKILL.md). **A draft**: it has not yet been used to do a job, and
it points at the clients, which still live in the companion hardware repo (docs/CURRENT-STATE.md).

Install it once per machine, so a session in any repo has it:

```bash
mkdir -p ~/.claude/skills/altium-bridge
cp skills/altium-bridge/SKILL.md ~/.claude/skills/altium-bridge/SKILL.md
```

## autodesign

Drives an autonomous spec-to-board PCB design run with the eda-agent MCP
server. See [autodesign/SKILL.md](autodesign/SKILL.md).

**Claude Code**: copy it into your project (or user) skills directory:

```bash
mkdir -p .claude/skills/autodesign
cp skills/autodesign/SKILL.md .claude/skills/autodesign/SKILL.md
```

Then `/autodesign` is available in that project.

**Other clients**: the same protocol is available without any skill file:
call the `design_autonomy_guide` tool, or invoke the `autonomous_design` MCP
prompt. Both need the design harness, which the Altium and EasyEDA backends
register and the KiCad backend does not.
See [../docs/AUTONOMOUS_DESIGN.md](../docs/AUTONOMOUS_DESIGN.md).
