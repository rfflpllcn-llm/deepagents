---
name: schema-reference
description: Complete database schema reference - table structures, columns, indexes, triggers, and views for the literary RAG system
---

# Database Schema Reference

Complete schema documentation for the PostgreSQL literary RAG database. Use this when you need detailed information about table structures, columns, relationships, indexes, or triggers.

## Table Schemas

### works
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| work_id | BIGSERIAL | PRIMARY KEY | Unique identifier for the work |
| title | TEXT | NOT NULL | Title of the literary work |
| author | TEXT | NOT NULL | Author name |
| notes | TEXT | | Additional notes |

**Unique Index:** `uq_works_title_author` on (title, author)

---

### editions
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| edition_id | BIGSERIAL | PRIMARY KEY | Unique identifier for the edition |
| work_id | BIGINT | NOT NULL, FK → works(work_id) | Reference to parent work |
| language | CHAR(2) | NOT NULL | ISO 639-1 language code (e.g., 'fr', 'en') |
| publisher | TEXT | | Publisher name |
| year | INTEGER | CHECK (year BETWEEN 1400 AND 2100) | Publication year |
| isbn | TEXT | | ISBN identifier |
| anna_archive_id | TEXT | | Anna's Archive identifier |
| notes | TEXT | | Additional notes |

**Unique Index:** `uq_editions_identity` on (work_id, language, publisher, anna_archive_id)

---

### chunks
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| chunk_id | BIGSERIAL | PRIMARY KEY | Unique identifier for the chunk |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Reference to parent edition |
| line_id | TEXT | NOT NULL | Stable cross-reference identifier (e.g., "FR77") |
| page | INTEGER | NOT NULL, CHECK (page > 0) | Page number |
| line_no | INTEGER | NOT NULL, CHECK (line_no > 0) | Line number on page |
| box | JSONB | NOT NULL, CHECK (4-element numeric array) | Bounding box [x0, y0, x1, y1] |
| text | TEXT | NOT NULL | OCR-extracted text content |
| text_hash | TEXT | GENERATED ALWAYS AS (md5(text)) STORED | Hash for deduplication |

**Unique Constraint:** `chunks_unique_pos` on (edition_id, page, line_no)

**Unique Index:** `uq_chunks_edition_lineid` on (edition_id, line_id)

**Indexes:**
- `idx_chunks_edition_page_line` on (edition_id, page, line_no) - fast lookup by position
- `idx_chunks_text_gin` GIN index on `to_tsvector('simple', text)` - full-text search
- `idx_chunks_text_hash` on (text_hash) - deduplication queries

---

### semantic_chunks
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| sc_pk | BIGSERIAL | PRIMARY KEY | Unique identifier for semantic chunk |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Reference to parent edition |
| sc_id | TEXT | NOT NULL | Semantic chunk identifier (e.g., "SC_001") |
| page_start | INTEGER | | Starting page number |
| page_end | INTEGER | CHECK (page_start ≤ page_end) | Ending page number |
| embedding_text | TEXT | | Text optimized for embedding models |
| embedding_summary | TEXT | | Condensed version for retrieval |
| paraphrase | TEXT | | Rewritten version |
| word_count | INTEGER | | Number of words |
| sentence_count | INTEGER | | Number of sentences |
| meta | JSONB | NOT NULL, DEFAULT '{}' | Extensible metadata (see JSONB Fields below) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT now() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT now() | Last update timestamp (auto-updated) |

**Unique Constraint:** `uq_semantic_chunks` on (edition_id, sc_id)

**Indexes:**
- `idx_semantic_chunks_edition` on (edition_id)
- `idx_semantic_chunks_meta_gin` GIN index on (meta jsonb_path_ops) - JSONB queries

**Trigger:** `trg_semantic_chunks_updated_at` - auto-updates `updated_at` on modification

---

### semantic_chunk_members
Junction table linking semantic chunks to their constituent raw chunks.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| sc_pk | BIGINT | NOT NULL, FK → semantic_chunks(sc_pk) ON DELETE CASCADE | Reference to parent semantic chunk |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Denormalized edition reference |
| line_id | TEXT | NOT NULL | Reference to raw chunk |
| ord | INTEGER | NOT NULL, CHECK (ord > 0) | Order within semantic chunk |

**Primary Key:** (sc_pk, line_id)

**Foreign Key:** (edition_id, line_id) → chunks(edition_id, line_id) ON DELETE CASCADE

**Indexes:**
- `idx_members_sc_ord` on (sc_pk, ord) - ordered member retrieval
- `idx_members_edition_lineid` on (edition_id, line_id) - reverse lookup

**Trigger:** `trg_member_edition_consistency` - ensures edition_id matches parent semantic_chunk

---

### micro_units
Higher-level narrative segments with interpretive metadata.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| mu_pk | BIGSERIAL | PRIMARY KEY | Unique identifier for micro-unit |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Reference to parent edition |
| unit_id | TEXT | NOT NULL | Micro-unit identifier (e.g., "MU_001") |
| page_start | INTEGER | | Starting page number |
| page_end | INTEGER | CHECK (page_start ≤ page_end) | Ending page number |
| summary | JSONB | NOT NULL, DEFAULT '{}' | Structured summary (see JSONB Fields below) |
| character_dynamics | JSONB | NOT NULL, DEFAULT '[]', CHECK (array type) | Character interactions (see JSONB Fields below) |
| story_threads | TEXT[] | NOT NULL, DEFAULT '{}' | Narrative threads this unit participates in |
| meta | JSONB | NOT NULL, DEFAULT '{}' | Extensible metadata |
| created_at | TIMESTAMP | NOT NULL, DEFAULT now() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT now() | Last update timestamp (auto-updated) |

**Unique Constraint:** `uq_micro_units` on (edition_id, unit_id)

**Indexes:**
- `idx_micro_units_edition` on (edition_id)
- `idx_micro_units_story_threads` GIN index on (story_threads) - array containment queries
- `idx_micro_units_character_dynamics` GIN index on (character_dynamics jsonb_path_ops)
- `idx_micro_units_narrative_function` on ((summary->>'narrative_function')) - function filtering

**Trigger:** `trg_micro_units_updated_at` - auto-updates `updated_at` on modification

---

### micro_unit_members
Junction table linking micro-units to their constituent semantic chunks.

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| mu_pk | BIGINT | NOT NULL, FK → micro_units(mu_pk) ON DELETE CASCADE | Reference to parent micro-unit |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Denormalized edition reference |
| sc_id | TEXT | NOT NULL | Reference to semantic chunk |
| ord | INTEGER | NOT NULL, CHECK (ord > 0) | Order within micro-unit |

**Primary Key:** (mu_pk, sc_id)

**Foreign Key:** (edition_id, sc_id) → semantic_chunks(edition_id, sc_id) ON DELETE CASCADE

**Indexes:**
- `idx_mu_members_ord` on (mu_pk, ord) - ordered member retrieval
- `idx_mu_members_edition_scid` on (edition_id, sc_id) - reverse lookup

**Trigger:** `trg_mu_member_edition_consistency` - ensures edition_id matches parent micro_unit

---

## JSONB Fields

### semantic_chunks.meta
May contain:
- `register` - linguistic register
- `interpretive_layers` - array of interpretations
- `retrieval_tags` - tags for retrieval
- `context_links` - links to related chunks
- `keywords` - keyword mapping
- `questions` - questions answered by this chunk

### micro_units.summary
Contains:
- `what_happens` - narrative summary
- `narrative_function` - function type (e.g., "apertura_sezione", "sviluppo", "climax", "risoluzione", "transizione")
- `significance` - interpretive significance

### micro_units.character_dynamics
Array of objects with:
- `from` - source character
- `to` - target character
- `relation_type` - type of relationship (e.g., "amicizia_intellettuale")
- `interaction` - interaction type (e.g., "provocazione_dialettica")
- `evolution` - how the relationship evolves

### chunks.box
Bounding box as `[x0, y0, x1, y1]` (4-element numeric array)

---

## Database Functions and Triggers

### check_member_edition_consistency()
**Purpose:** Ensures `semantic_chunk_members.edition_id` matches parent `semantic_chunk`'s `edition_id`

**Trigger:** `trg_member_edition_consistency` on semantic_chunk_members (BEFORE INSERT OR UPDATE)

---

### check_mu_member_edition_consistency()
**Purpose:** Ensures `micro_unit_members.edition_id` matches parent `micro_unit`'s `edition_id`

**Trigger:** `trg_mu_member_edition_consistency` on micro_unit_members (BEFORE INSERT OR UPDATE)

---

### update_timestamp()
**Purpose:** Auto-updates `updated_at` field to current timestamp

**Triggers:**
- `trg_semantic_chunks_updated_at` on semantic_chunks (BEFORE UPDATE)
- `trg_micro_units_updated_at` on micro_units (BEFORE UPDATE)

---

## Pre-Built Views

### v_semantic_chunks_summary
Semantic chunk with member count, page range, and member line IDs.

**Columns:** sc_pk, edition_id, sc_id, page_start, page_end, word_count, sentence_count, member_count, member_line_ids (array), created_at, updated_at

---

### v_semantic_chunk_full_text
Full concatenated text for each semantic chunk (raw chunks joined in order).

**Columns:** sc_pk, sc_id, edition_id, full_text

---

### v_micro_units_summary
Micro-unit with narrative summary, story threads, and semantic chunk member IDs.

**Columns:** mu_pk, edition_id, unit_id, page_start, page_end, what_happens, narrative_function, significance, story_threads, semantic_chunk_count, semantic_chunk_ids (array), created_at, updated_at

---

### v_character_interactions
Character interactions flattened from `micro_units.character_dynamics` JSONB array.

**Columns:** mu_pk, edition_id, unit_id, page_start, page_end, character_from, character_to, relation_type, interaction, evolution

---

### v_story_thread_units
Story thread participation - which micro-units belong to which narrative threads.

**Columns:** edition_id, story_thread, mu_pk, unit_id, page_start, page_end, what_happens

---

## Query Tips

**Full-text search on chunks:**
```sql
WHERE to_tsvector('simple', text) @@ to_tsquery('simple', 'search & terms')
```

**JSONB field extraction:**
```sql
summary->>'what_happens'  -- Get as text
summary->'keywords'        -- Get as JSON
meta @> '{"register": "formal"}'  -- Contains check
meta ? 'keywords'          -- Has key check
```

**Array operations:**
```sql
WHERE story_threads @> ARRAY['thread_name']  -- Contains element
SELECT unnest(story_threads) AS thread FROM micro_units LIMIT 10  -- Unnest to rows
```

**Character search in JSONB array:**
```sql
WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements(character_dynamics) cd
    WHERE cd->>'from' ILIKE '%character%' OR cd->>'to' ILIKE '%character%'
)
```
