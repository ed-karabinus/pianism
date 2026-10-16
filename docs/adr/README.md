# Architecture decision records

Significant technical decisions are recorded here in [MADR](https://adr.github.io/madr/) style:
context, options considered, the decision, and its consequences. Write a new record when a change
adds a module, a dependency, a persistent model change, or departs from an earlier decision.
Never edit an accepted record's decision; supersede it with a new one. Each record's status is in
its own file.

| # | Decision |
| --- | --- |
| [1](0001-platform-independent-core.md) | A platform-independent core, tested on Linux |
| [2](0002-project-structure.md) | Thin Xcode project plus local Swift packages |
| [3](0003-running-session-storage.md) | The running session lives in the App Group, not the synced store |
| [4](0004-synced-data-model.md) | Finished sessions and tags in SwiftData, mapped to core values and synced through CloudKit |
| [5](0005-code-health-checks.md) | Unused code found by Periphery 3.8.0, and mutation testing by a script in the repository |
| [6](0006-schema-v1-before-deploy.md) | Schema v1 gains a record version, a time zone and a deleted mark before it ships |
| [7](0007-outbox-when-history-cant-save.md) | Finished sessions wait in an outbox when history can't save them |
