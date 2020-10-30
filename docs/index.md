# Home

Lionstore is meant to be a low impact, reliable alternative to ProfileService and DataStore2.

Lionstore aims to be as minimal as possible yet powerful. Having the capability of ProfileService's session locking, and using backups like DataStore2, lionstore provides a robust way to save your data.

Lionstore is fault tolerant. If your data becomes corrupted, no problem; enter `habitats`, a way to catch errors and mark them from saving before it gets deleted.
`Partitions` are a powerful feature of the library. The reason why it's so lightweight is that it gives you the ability to split the allocation of your data into multiple partitions. No need for ordered data stores anymore. Every time a player's data gets loaded, a partition gets discarded so there's a revision history based on how many partitions exist.

The API is very minimal. Everything is already implemented for you. You don't need to store player objects in tables, it does it for you. Session locking means that if a player rejoins while the past server is saving, data won't be lost.

Lionstore is low impact. Data is only retrieved once, and periodically sends a lock request every 4 minutes per session.

There's no set functions, only `update`. Data automatically get reconciled upon load.
