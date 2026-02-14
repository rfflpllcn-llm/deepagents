---
name: schema-reference
description: Complete database schema reference for the literary RAG system
---

# Schema Reference

## Tables

**works** — Literary works
- work_id BIGSERIAL PK, title TEXT NOT NULL, author TEXT NOT NULL, notes TEXT
- Unique: (title, author)

**editions** — Published editions of works
- edition_id BIGSERIAL PK, work_id BIGINT FK→works, language CHAR(2) NOT NULL, publisher TEXT, year INT, isbn TEXT, anna_archive_id TEXT, notes TEXT
- Unique: (work_id, language, publisher, anna_archive_id)

**chunks** — Raw OCR text lines
- chunk_id BIGSERIAL PK, edition_id BIGINT FK→editions, line_id TEXT NOT NULL, page INT NOT NULL, line_no INT NOT NULL, box JSONB [x0,y0,x1,y1], text TEXT NOT NULL, text_hash TEXT (generated md5)
- Unique: (edition_id, page, line_no) and (edition_id, line_id)
- GIN index on to_tsvector('simple', text) for full-text search

**semantic_chunks** — Grouped chunks with summaries
- sc_pk BIGSERIAL PK, edition_id BIGINT FK→editions, sc_id TEXT NOT NULL, page_start INT, page_end INT, embedding_text TEXT, embedding_summary TEXT, paraphrase TEXT, word_count INT, sentence_count INT, meta JSONB, created_at TIMESTAMP, updated_at TIMESTAMP
- Unique: (edition_id, sc_id)
- GIN index on meta

**semantic_chunk_members** — Links semantic_chunks → chunks
- PK: (sc_pk FK→semantic_chunks, line_id), edition_id BIGINT FK→editions, ord INT

**micro_units** — Narrative segments with interpretive metadata
- mu_pk BIGSERIAL PK, edition_id BIGINT FK→editions, unit_id TEXT NOT NULL, page_start INT, page_end INT, summary JSONB, character_dynamics JSONB[], story_threads TEXT[], meta JSONB, created_at TIMESTAMP, updated_at TIMESTAMP
- Unique: (edition_id, unit_id)
- GIN indexes on story_threads, character_dynamics, summary->>'narrative_function'

**micro_unit_members** — Links micro_units → semantic_chunks
- PK: (mu_pk FK→micro_units, sc_id), edition_id BIGINT FK→editions, ord INT

## JSONB Fields

**semantic_chunks.meta**: register, interpretive_layers[], retrieval_tags, context_links, keywords, questions
**micro_units.summary**: what_happens (text), narrative_function (apertura_sezione|sviluppo|climax|risoluzione|transizione), significance (text)
**micro_units.character_dynamics**: Array of {from, to, relation_type, interaction, evolution}

## Views

- **v_semantic_chunks_summary** — sc_pk, edition_id, sc_id, page_start, page_end, word_count, sentence_count, member_count, member_line_ids[]
- **v_semantic_chunk_full_text** — sc_pk, sc_id, edition_id, full_text (concatenated chunks)
- **v_micro_units_summary** — mu_pk, edition_id, unit_id, page_start, page_end, what_happens, narrative_function, significance, story_threads, semantic_chunk_count, semantic_chunk_ids[]
- **v_character_interactions** — mu_pk, edition_id, unit_id, page_start, page_end, character_from, character_to, relation_type, interaction, evolution
- **v_story_thread_units** — edition_id, story_thread, mu_pk, unit_id, page_start, page_end, what_happens

## Query Syntax

Full-text search: `WHERE to_tsvector('simple', text) @@ to_tsquery('simple', 'term')`
JSONB text: `summary->>'what_happens'` | JSONB object: `summary->'keywords'` | Contains: `meta @> '{"key":"val"}'` | Has key: `meta ? 'key'`
Array contains: `WHERE story_threads @> ARRAY['thread']` | Unnest: `SELECT unnest(story_threads) FROM micro_units LIMIT 10`
Character search: `WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(character_dynamics) cd WHERE cd->>'from' ILIKE '%name%')`
