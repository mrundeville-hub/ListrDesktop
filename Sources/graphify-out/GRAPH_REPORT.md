# Graph Report - Sources  (2026-06-23)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 162 nodes · 285 edges · 12 communities (10 shown, 2 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 2 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `cd2d6e5e`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]

## God Nodes (most connected - your core abstractions)
1. `String` - 20 edges
2. `Book` - 14 edges
3. `FB2XMLDelegate` - 12 edges
4. `Status` - 11 edges
5. `BookFormat` - 11 edges
6. `Status` - 10 edges
7. `ImportedBook` - 10 edges
8. `Chapter` - 9 edges
9. `VoiceEngine` - 9 edges
10. `LibraryStore` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Book` --implements--> `Codable`  [EXTRACTED]
  ListrDesktop/Models/Book.swift →   _Bridges community 4 → community 6_
- `Book` --implements--> `Hashable`  [EXTRACTED]
  ListrDesktop/Models/Book.swift →   _Bridges community 4 → community 2_
- `Book` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Models/Book.swift →   _Bridges community 4 → community 0_
- `BookFormat` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Models/BookFormat.swift →   _Bridges community 0 → community 2_
- `LibraryPersistenceService` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Services/LibraryPersistenceService.swift →   _Bridges community 0 → community 6_

## Import Cycles
- None detected.

## Communities (12 total, 2 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.14
Nodes (19): Archive, BookFormat, Data, URL, LocalizedError, Sendable, BookImportError, emptyBook (+11 more)

### Community 1 - "Community 1"
Cohesion: 0.13
Nodes (23): Chapter, Book, Chapter, Color, String, Book, Color, String (+15 more)

### Community 2 - "Community 2"
Cohesion: 0.10
Nodes (22): CaseIterable, Hashable, Identifiable, URL, Int, UUID, BookFormat, epub (+14 more)

### Community 3 - "Community 3"
Cohesion: 0.21
Nodes (10): Bool, Bool, Chapter, String, NSObject, EPUBContainerParser, EPUBPackageParser, FB2XMLDelegate (+2 more)

### Community 4 - "Community 4"
Cohesion: 0.14
Nodes (14): Date, Double, Chapter, Double, Int, UUID, Book, Status (+6 more)

### Community 5 - "Community 5"
Cohesion: 0.29
Nodes (5): LibraryPersistenceService, Book, String, URL, LibraryStore

### Community 6 - "Community 6"
Cohesion: 0.24
Nodes (7): Codable, Book, URL, JSONDecoder, JSONEncoder, LibraryPersistenceService, PersistedLibrary

### Community 7 - "Community 7"
Cohesion: 0.33
Nodes (5): String, URL, VoiceEngine, PlannedTTSService, TTSService

### Community 8 - "Community 8"
Cohesion: 0.29
Nodes (6): Bool, Double, Int, String, VoiceEngine, ConversionStore

### Community 9 - "Community 9"
Cohesion: 0.50
Nodes (3): App, ListrDesktopApp, Scene

## Knowledge Gaps
- **49 isolated node(s):** `Scene`, `imported`, `queued`, `converting`, `ready` (+44 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ImportedBook` connect `Community 0` to `Community 3`?**
  _High betweenness centrality (0.172) - this node is a cross-community bridge._
- **Why does `String` connect `Community 3` to `Community 0`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._
- **Why does `BookImportService` connect `Community 0` to `Community 5`?**
  _High betweenness centrality (0.086) - this node is a cross-community bridge._
- **What connects `Scene`, `imported`, `queued` to the rest of the system?**
  _49 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.1282051282051282 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.09538461538461539 - nodes in this community are weakly interconnected._