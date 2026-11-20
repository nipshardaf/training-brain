# Changes made by 大支野 (OpenMausBot chief of staff), for Claude Code

## v4.18 (20 Nov 2026)
- Bug: after a layoff, Log sets prefilled 60 lb for Face Pull while the coach said 40 lb.
- Cause: coach uses energyTargets().sugW; prefill/target pill use computeProgressionTarget, which ignored the layoff.
- Fix in index.html: computeProgressionTarget wraps _progTargetRaw through _returnEase (caps at the coach number; assisted lifts go up). Helpers _gymLayoffBeforeToday and _returnFactor sit just above it.
- Shipped the usual way: APP_VERSION, CHANGELOG entry, CLAUDE.md note, commit, push.
- Tested in a 375px browser frame only, not on a real iPhone.
