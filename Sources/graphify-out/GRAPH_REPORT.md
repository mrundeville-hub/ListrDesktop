# Graph Report - Sources  (2026-06-23)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 146 nodes · 252 edges · 12 communities (10 shown, 2 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 1 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

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
1. `String` - 19 edges
2. `Book` - 12 edges
3. `FB2XMLDelegate` - 11 edges
4. `Status` - 10 edges
5. `BookFormat` - 10 edges
6. `ImportedBook` - 10 edges
7. `Status` - 9 edges
8. `Chapter` - 8 edges
9. `VoiceEngine` - 8 edges
10. `BookImportError` - 7 edges

## Surprising Connections (you probably didn't know these)
- `Book` --implements--> `Identifiable`  [EXTRACTED]
  ListrDesktop/Models/Book.swift →   _Bridges community 1 → community 4_
- `Book` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Models/Book.swift →   _Bridges community 1 → community 5_
- `BookFormat` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Models/BookFormat.swift →   _Bridges community 5 → community 4_
- `ImportedBook` --implements--> `Sendable`  [EXTRACTED]
  ListrDesktop/Services/BookImportService.swift →   _Bridges community 5 → community 0_
- `BookImportError` --references--> `String`  [EXTRACTED]
  ListrDesktop/Services/BookImportService.swift → ListrDesktop/Services/BookImportService.swift  _Bridges community 0 → community 3_

## Import Cycles
- None detected.

## Communities (12 total, 2 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.15
Nodes (17): Archive, BookFormat, Data, URL, LocalizedError, BookImportError, emptyBook, invalidEPUB (+9 more)

### Community 1 - "Community 1"
Cohesion: 0.10
Nodes (23): Date, Hashable, Chapter, Double, Int, UUID, Int, UUID (+15 more)

### Community 2 - "Community 2"
Cohesion: 0.18
Nodes (18): Chapter, Book, Chapter, Color, String, View, ContentView, ChapterCard (+10 more)

### Community 3 - "Community 3"
Cohesion: 0.22
Nodes (9): Bool, Chapter, String, NSObject, EPUBContainerParser, EPUBPackageParser, FB2XMLDelegate, TextCleaner (+1 more)

### Community 4 - "Community 4"
Cohesion: 0.14
Nodes (12): CaseIterable, Identifiable, URL, BookFormat, epub, fb2, plainText, VoiceEngine (+4 more)

### Community 5 - "Community 5"
Cohesion: 0.27
Nodes (6): Book, String, URL, Sendable, BookImportService, LibraryStore

### Community 6 - "Community 6"
Cohesion: 0.33
Nodes (5): String, URL, VoiceEngine, PlannedTTSService, TTSService

### Community 7 - "Community 7"
Cohesion: 0.29
Nodes (6): Bool, Double, Int, String, VoiceEngine, ConversionStore

### Community 8 - "Community 8"
Cohesion: 0.40
Nodes (5): Book, Color, String, BookRow, SidebarView

### Community 9 - "Community 9"
Cohesion: 0.50
Nodes (3): App, ListrDesktopApp, Scene

## Knowledge Gaps
- **44 isolated node(s):** `Scene`, `imported`, `queued`, `converting`, `ready` (+39 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ImportedBook` connect `Community 0` to `Community 3`, `Community 5`?**
  _High betweenness centrality (0.160) - this node is a cross-community bridge._
- **Why does `BookImportService` connect `Community 5` to `Community 0`?**
  _High betweenness centrality (0.096) - this node is a cross-community bridge._
- **Why does `String` connect `Community 3` to `Community 0`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **What connects `Scene`, `imported`, `queued` to the rest of the system?**
  _44 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.10333333333333333 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._