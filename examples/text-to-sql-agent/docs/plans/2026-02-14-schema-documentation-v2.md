# Database Schema Documentation Implementation Plan (Revised)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace runtime schema discovery with on-demand schema reference via progressive disclosure

**Architecture:** Remove discovery tools (`sql_db_list_tables`, `sql_db_schema`), create schema-reference skill with complete schema docs, keep query checker tool, update AGENTS.md to remove discovery references, simplify query-writing skill

**Tech Stack:** DeepAgents, LangChain, PostgreSQL, langchain_community.tools

---

## Task 1: Create schema-reference Skill

**Files:**
- Create: `skills/schema-reference/SKILL.md`
- Reference: `01_schema.sql`

**Step 1: Create skill directory**

```bash
mkdir -p skills/schema-reference
```

**Step 2: Create SKILL.md with complete schema documentation**

Create `skills/schema-reference/SKILL.md` with frontmatter and full schema from `01_schema.sql` (see content below).

**Step 3: Verify skill file structure**

```bash
head -n 10 skills/schema-reference/SKILL.md
```

Expected output: Should show YAML frontmatter with `name: schema-reference` and `description:`.

**Step 4: Commit the new skill**

```bash
git add skills/schema-reference/
git commit -m "feat: add schema-reference skill with complete schema docs

Progressive disclosure - schema loaded only when agent invokes this skill.
Contains all tables, columns, indexes, triggers, and views from 01_schema.sql.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

### schema-reference SKILL.md Content

```markdown
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
SELECT unnest(story_threads) AS thread FROM micro_units  -- Unnest to rows
```

**Character search in JSONB array:**
```sql
WHERE EXISTS (
    SELECT 1 FROM jsonb_array_elements(character_dynamics) cd
    WHERE cd->>'from' ILIKE '%character%' OR cd->>'to' ILIKE '%character%'
)
```
```

---

## Task 2: Update AGENTS.md to Remove Discovery References

**Files:**
- Modify: `AGENTS.md:8-9,89,97`

**Step 1: Update "Your Role" section (lines 7-12)**

Replace lines 8-9:
```markdown
1. Explore the available database tables
2. Examine relevant table schemas
```

With:
```markdown
1. Reference database schema via schema-reference skill when needed
2. Validate SQL syntax with sql_db_query_checker
```

**Step 2: Update "Planning for Complex Questions" section (line 89)**

Replace line 89:
```markdown
2. List which tables you'll need to examine
```

With:
```markdown
2. Invoke schema-reference skill if you need detailed table information
```

**Step 3: Update "Example Approach" section (line 97)**

Replace line 97:
```markdown
- List tables → Find chunks table → Query schema → Execute COUNT query with WHERE page = 42
```

With:
```markdown
- Reference schema → Write query → Execute COUNT query with WHERE page = 42
```

**Step 4: Verify changes**

```bash
grep -n "schema-reference" AGENTS.md
```

Expected: Should show the updated lines with "schema-reference skill" references.

**Step 5: Commit the AGENTS.md updates**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md to reference schema-reference skill

Remove discovery tool references (lines 8-9, 89, 97).
Agent now invokes schema-reference skill instead of using discovery tools.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Simplify query-writing Skill

**Files:**
- Modify: `skills/query-writing/SKILL.md`

**Step 1: Replace skill content with simplified version**

Replace entire content of `skills/query-writing/SKILL.md` with:

```markdown
---
name: query-writing
description: For writing and executing SQL queries against the literary RAG database
---

# Query Writing Skill

## When to Use This Skill

Use this skill when you need to answer a question by writing and executing a SQL query.

## Workflow

1. **Understand the question** - What data is being requested?
2. **Reference schema** - Invoke schema-reference skill if you need detailed table information
3. **Write the query** - Construct syntactically correct PostgreSQL query
4. **Validate** - Use sql_db_query_checker to validate syntax before execution
5. **Execute** - Run with sql_db_query tool
6. **Format answer** - Present results clearly to the user

## PostgreSQL Query Guidelines

- **READ-ONLY:** Only SELECT queries allowed (no INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE/CREATE)
- **Limit results:** Always use LIMIT (default 5 rows unless user specifies otherwise)
- **Use aliases:** Make queries readable with table aliases (e.g., `FROM works w JOIN editions e ON e.work_id = w.work_id`)
- **Select relevant columns:** Avoid SELECT * - query only what you need
- **Order results:** Use ORDER BY to show most relevant/interesting data first
- **Use CTEs:** For complex queries, use WITH clauses for readability

## PostgreSQL-Specific Syntax

**JSONB operators:**
- `->>` - Get field as text: `summary->>'what_happens'`
- `->` - Get field as JSON: `summary->'keywords'`
- `@>` - Contains: `meta @> '{"register": "formal"}'`
- `?` - Has key: `meta ? 'keywords'`

**Full-text search:**
```sql
WHERE to_tsvector('simple', text) @@ to_tsquery('simple', 'search & terms')
```

**Array operations:**
```sql
-- Contains all elements
WHERE story_threads @> ARRAY['thread_name']

-- Unnest array to rows
SELECT unnest(story_threads) AS thread FROM micro_units
```

**Regex matching:**
```sql
WHERE text ~* 'pattern'  -- Case-insensitive
WHERE text ~ 'pattern'   -- Case-sensitive
```

**Type casting:**
```sql
SELECT year::text, count(*)::integer
```

## Common Query Patterns

**Multi-level drill-down (micro_unit → semantic_chunks → chunks):**
```sql
WITH mu_content AS (
    SELECT
        mu.unit_id,
        sc.sc_id,
        string_agg(c.text, ' ' ORDER BY scm.ord) AS chunk_text
    FROM micro_units mu
    JOIN micro_unit_members mum ON mum.mu_pk = mu.mu_pk
    JOIN semantic_chunks sc ON sc.edition_id = mum.edition_id AND sc.sc_id = mum.sc_id
    JOIN semantic_chunk_members scm ON scm.sc_pk = sc.sc_pk
    JOIN chunks c ON c.edition_id = scm.edition_id AND c.line_id = scm.line_id
    WHERE mu.edition_id = 1 AND mu.unit_id = 'MU_001'
    GROUP BY mu.unit_id, sc.sc_id
)
SELECT * FROM mu_content;
```

**Search in JSONB arrays:**
```sql
-- Find micro-units involving a specific character
SELECT unit_id, summary->>'what_happens'
FROM micro_units
WHERE edition_id = 1
  AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(character_dynamics) cd
      WHERE cd->>'from' ILIKE '%character%'
         OR cd->>'to' ILIKE '%character%'
  )
ORDER BY page_start;
```

**Use pre-built views:**
```sql
-- Semantic chunk summaries
SELECT * FROM v_semantic_chunks_summary WHERE edition_id = 1 LIMIT 5;

-- Micro-unit summaries
SELECT * FROM v_micro_units_summary WHERE edition_id = 1 LIMIT 5;

-- Character interactions
SELECT * FROM v_character_interactions WHERE character_from ILIKE '%name%';

-- Story thread participation
SELECT * FROM v_story_thread_units WHERE story_thread = 'thread_name';
```

## Tips

- For complex analytical questions, break down your thinking before writing the query
- Invoke schema-reference skill for detailed table structures and column names
- Use sql_db_query_checker to validate syntax before executing
- Check pre-built views (v_semantic_chunks_summary, v_micro_units_summary, etc.) for common lookups
- If a query fails, read the error message carefully and check your syntax
```

**Step 2: Verify skill syntax**

```bash
head -n 5 skills/query-writing/SKILL.md
```

Expected output:
```
---
name: query-writing
description: For writing and executing SQL queries against the literary RAG database
---
```

**Step 3: Commit the simplified skill**

```bash
git add skills/query-writing/SKILL.md
git commit -m "refactor: simplify query-writing skill

Reference schema-reference skill instead of discovery tools.
Add query validation step with sql_db_query_checker.
Reduced from 117 lines to ~60 lines.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Delete schema-exploration Skill

**Files:**
- Delete: `skills/schema-exploration/` (entire directory)

**Step 1: Remove the schema-exploration directory**

```bash
rm -rf skills/schema-exploration/
```

**Step 2: Verify deletion**

```bash
ls -la skills/
```

Expected output should show only `query-writing/` and `schema-reference/`, NOT `schema-exploration/`

**Step 3: Commit the deletion**

```bash
git add skills/
git commit -m "remove: delete schema-exploration skill

Replaced by schema-reference skill. Discovery tools will be removed,
making this skill obsolete.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Modify agent.py to Use Query and Checker Tools

**Files:**
- Modify: `agent.py:1-50`

**Step 1: Add imports for query and checker tools**

After line 9 (after `from langchain_community.utilities import SQLDatabase`), add:

```python
from langchain_community.tools import QuerySQLDatabaseTool, QuerySQLCheckerTool
```

**Step 2: Replace toolkit creation with direct tool creation**

Replace lines 44-46:
```python
# Create SQL toolkit and get tools
toolkit = SQLDatabaseToolkit(db=db, llm=model)
sql_tools = toolkit.get_tools()
```

With:
```python
# Create only query execution and validation tools (no discovery tools)
sql_tools = [
    QuerySQLDatabaseTool(
        db=db,
        description="Execute a SQL query against the database. Returns the query results."
    ),
    QuerySQLCheckerTool(
        db=db,
        llm=model,
        description="Validate SQL query syntax before execution. Use this to check queries for errors."
    )
]
```

**Step 3: Comment out or remove unused import (line 9)**

Change line 9:
```python
from langchain_community.agent_toolkits import SQLDatabaseToolkit
```

To:
```python
# from langchain_community.agent_toolkits import SQLDatabaseToolkit  # No longer needed
```

**Step 4: Verify the modified file**

```bash
grep -A10 "QuerySQLDatabaseTool" agent.py
```

Expected: Should show the new tool creation code.

**Step 5: Commit the agent.py changes**

```bash
git add agent.py
git commit -m "refactor: use only query execution and validation tools

Replace SQLDatabaseToolkit with direct tool creation.
Use QuerySQLDatabaseTool and QuerySQLCheckerTool (correct non-deprecated imports).
Remove discovery tools (sql_db_list_tables, sql_db_schema).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Verify Tool Availability

**Files:**
- Modify (temporarily): `agent.py:53`

**Step 1: Add debug print to verify tools**

After the `sql_tools` creation (around line 53), add:
```python
# Debug: verify only query and checker tools are loaded
print(f"Available SQL tools: {[tool.name for tool in sql_tools]}")
```

**Step 2: Run agent to check tools**

```bash
uv run python agent.py "How many works are in the database?"
```

Expected output should include:
```
Available SQL tools: ['sql_db_query', 'sql_db_query_checker']
```

Should NOT include: `sql_db_list_tables` or `sql_db_schema`

**Step 3: Remove debug print**

Remove the debug print line added in Step 1.

**Step 4: Commit removal of debug code**

```bash
git add agent.py
git commit -m "chore: remove debug print for tool verification

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Test Simple Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test simple single-table query**

```bash
uv run python agent.py "How many works are in the database?"
```

Expected: Agent should successfully query the `works` table and return count without using discovery tools.

**Step 2: Verify schema-reference skill invocation (if needed)**

If the agent needs table information, it should invoke the schema-reference skill (not discovery tools).

**Step 3: Verify no discovery tool usage**

Check agent output - it should NOT contain calls to:
- `sql_db_list_tables`
- `sql_db_schema`

It should ONLY use:
- `sql_db_query`
- `sql_db_query_checker` (if validating)

---

## Task 8: Test Join Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test multi-table join query**

```bash
uv run python agent.py "List all editions with their work titles and authors"
```

Expected: Agent should join `works` and `editions` tables. May invoke schema-reference skill if it needs schema details.

**Step 2: Verify schema-reference skill usage**

Check if agent invokes schema-reference skill to understand table relationships.

**Step 3: Verify query validation**

Check if agent uses sql_db_query_checker to validate the query before execution.

---

## Task 9: Test Complex JSONB Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test JSONB query**

```bash
uv run python agent.py "Which narrative threads appear most frequently in micro units?"
```

Expected: Agent should query `micro_units.story_threads` array field using PostgreSQL array operators.

**Step 2: Verify schema-reference skill provides JSONB syntax help**

Agent should invoke schema-reference skill to understand JSONB structure and syntax.

**Step 3: Verify JSONB syntax usage**

Check that agent uses correct PostgreSQL syntax for arrays (e.g., `unnest()`, `@>`, etc.).

---

## Task 10: Test Full-Text Search

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test full-text search query**

```bash
uv run python agent.py "Find chunks containing the word 'guerre'"
```

Expected: Agent should use the GIN index with `to_tsvector` and `to_tsquery`.

**Step 2: Verify schema-reference skill provides index information**

Agent should invoke schema-reference skill to learn about the full-text search index.

**Step 3: Verify full-text search syntax**

Check that agent uses:
```sql
WHERE to_tsvector('simple', text) @@ to_tsquery('simple', 'guerre')
```

---

## Task 11: Test View Usage

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test query using pre-built views**

```bash
uv run python agent.py "Show me a summary of the first 3 semantic chunks"
```

Expected: Agent should use `v_semantic_chunks_summary` view.

**Step 2: Verify schema-reference skill documents views**

Agent should invoke schema-reference skill to learn about available views.

**Step 3: Verify view usage**

Check that agent queries the view instead of manually joining tables.

---

## Task 12: Test Error Handling - Unauthorized Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test write operation rejection**

```bash
uv run python agent.py "Delete all works"
```

Expected: Agent should refuse based on safety rules in AGENTS.md, or database should reject with permission error.

**Step 2: Verify error message is clear**

Check that user receives clear explanation that write operations are not allowed.

---

## Task 13: Test Error Handling - Invalid Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test query with syntax error**

```bash
uv run python agent.py "Show me data where syntax is completely invalid SQL"
```

Expected: sql_db_query_checker should catch the syntax error before execution.

**Step 2: Verify query checker catches error**

Check that agent uses sql_db_query_checker and catches the error with helpful message.

**Step 3: Test invalid table query**

```bash
uv run python agent.py "Show me data from nonexistent_table"
```

Expected: Agent should either:
- Check schema-reference skill, see table doesn't exist, and inform user
- Execute query, get error, and explain error to user

---

## Task 14: Final Verification and Summary

**Files:**
- None (documentation task)

**Step 1: Review all changes**

```bash
git log --oneline -15
```

Expected: Should see commits for:
1. Created schema-reference skill
2. Updated AGENTS.md
3. Simplified query-writing skill
4. Deleted schema-exploration skill
5. Modified agent.py
6. Various test verification commits

**Step 2: Verify success criteria**

Check all criteria from design document:
- [x] schema-reference skill contains comprehensive schema documentation
- [x] AGENTS.md updated to remove discovery tool references (~105 lines, no growth)
- [x] Agent has only `sql_db_query` and `sql_db_query_checker` tools
- [x] schema-exploration skill is removed
- [x] query-writing skill is simplified (~60 lines)
- [x] All test queries execute successfully
- [x] Agent invokes schema-reference skill when needed (progressive disclosure)
- [x] Query checker validates syntax before execution
- [x] Smaller baseline prompt (schema loaded on-demand)
- [x] Clear error messages for invalid queries
- [x] Correct imports used (QuerySQLDatabaseTool not deprecated version)

**Step 3: Measure baseline prompt size (optional)**

Compare AGENTS.md size before/after:
```bash
wc -l AGENTS.md
```

Expected: ~105 lines (no significant growth from original)

**Step 4: Create final summary (if needed)**

If any final cleanup is needed, commit it:
```bash
git add .
git commit -m "chore: finalize schema documentation implementation

All tests passing. Agent uses schema-reference skill (progressive disclosure)
instead of runtime discovery tools. Query validation working.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Success Criteria

- [x] schema-reference skill created with detailed tables, indexes, triggers, views
- [x] AGENTS.md updated (lines 8-9, 89, 97), stays lean (~105 lines)
- [x] query-writing skill simplified (~60 lines), references schema-reference
- [x] schema-exploration skill deleted
- [x] agent.py uses QuerySQLDatabaseTool and QuerySQLCheckerTool (correct imports)
- [x] Simple query test passes
- [x] Join query test passes
- [x] JSONB query test passes
- [x] Full-text search test passes
- [x] View query test passes
- [x] Write operation rejected (safety)
- [x] Query checker catches syntax errors
- [x] Invalid table query handled gracefully
- [x] Agent invokes schema-reference skill when needed (progressive disclosure working)
- [x] Smaller baseline prompt confirmed (schema not in AGENTS.md)

## Notes

- Schema documentation in schema-reference skill must be kept in sync with 01_schema.sql manually
- If schema changes, update skills/schema-reference/SKILL.md before deploying
- Progressive disclosure confirmed: baseline prompt stays small, schema loaded only when invoked
- Query validation reduces wasted tokens on failed executions
