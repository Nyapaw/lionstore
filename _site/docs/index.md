# Home

Lionstore is meant to be a low impact, reliable alternative to ProfileService and DataStore2.

Lionstore aims to be as minimal as possible yet powerful. Having the capability of ProfileService's session locking, and using backups like DataStore2, lionstore provides a robust way to save your data.

Lionstore is fault tolerant. If your data becomes corrupted, no problem; enter `habitats`, a way to catch errors and mark them from saving before it gets deleted.
`Partitions` are a powerful feature of the library. The reason why it's so lightweight is that it gives you the ability to split the allocation of your data into multiple partitions. No need for ordered data stores anymore.

The API is very minimal. Everything is already implemented for you. You don't need to store player objects in tables, it does it for you. Session locking means that if a player rejoins while the past server is saving, data won't be lost.