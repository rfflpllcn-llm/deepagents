# Database Schema Documentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace runtime schema discovery with comprehensive schema documentation in AGENTS.md

**Architecture:** Remove `sql_db_list_tables` and `sql_db_schema` tools, enhance AGENTS.md with complete schema from 01_schema.sql, simplify query-writing skill, delete schema-exploration skill

**Tech Stack:** DeepAgents, LangChain, PostgreSQL, langchain_community.tools.sql_database

---

## Task 1: Enhance AGENTS.md with Complete Schema Documentation

**Files:**
- Modify: `AGENTS.md`
- Reference: `01_schema.sql`

**Step 1: Add detailed table schemas section**

Insert after line 56 (after the existing Key Relationships section) in AGENTS.md:

```markdown

## Detailed Table Schemas

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
| language | CHAR(2) | NOT NULL | ISO 639-1 language code |
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
- `idx_chunks_edition_page_line` on (edition_id, page, line_no)
- `idx_chunks_text_gin` GIN index on `to_tsvector('simple', text)` for full-text search
- `idx_chunks_text_hash` on (text_hash)

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
| meta | JSONB | NOT NULL, DEFAULT '{}' | Extensible metadata (register, interpretive_layers, retrieval_tags, context_links, keywords, questions) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT now() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT now() | Last update timestamp |

**Unique Constraint:** `uq_semantic_chunks` on (edition_id, sc_id)
**Indexes:**
- `idx_semantic_chunks_edition` on (edition_id)
- `idx_semantic_chunks_meta_gin` GIN index on (meta jsonb_path_ops)

**Trigger:** `trg_semantic_chunks_updated_at` - auto-updates updated_at on modification

---

### semantic_chunk_members
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| sc_pk | BIGINT | NOT NULL, FK → semantic_chunks(sc_pk) ON DELETE CASCADE | Reference to parent semantic chunk |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Denormalized edition reference |
| line_id | TEXT | NOT NULL, FK → (edition_id, line_id) in chunks | Reference to raw chunk |
| ord | INTEGER | NOT NULL, CHECK (ord > 0) | Order within semantic chunk |

**Primary Key:** (sc_pk, line_id)
**Foreign Key:** (edition_id, line_id) → chunks(edition_id, line_id) ON DELETE CASCADE
**Indexes:**
- `idx_members_sc_ord` on (sc_pk, ord)
- `idx_members_edition_lineid` on (edition_id, line_id)

**Trigger:** `trg_member_edition_consistency` - ensures edition_id matches parent semantic_chunk

---

### micro_units
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| mu_pk | BIGSERIAL | PRIMARY KEY | Unique identifier for micro-unit |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Reference to parent edition |
| unit_id | TEXT | NOT NULL | Micro-unit identifier (e.g., "MU_001") |
| page_start | INTEGER | | Starting page number |
| page_end | INTEGER | CHECK (page_start ≤ page_end) | Ending page number |
| summary | JSONB | NOT NULL, DEFAULT '{}' | Structured summary (what_happens, narrative_function, significance) |
| character_dynamics | JSONB | NOT NULL, DEFAULT '[]', CHECK (array type) | Character interactions [{from, to, relation_type, interaction, evolution}] |
| story_threads | TEXT[] | NOT NULL, DEFAULT '{}' | Narrative threads this unit participates in |
| meta | JSONB | NOT NULL, DEFAULT '{}' | Extensible metadata |
| created_at | TIMESTAMP | NOT NULL, DEFAULT now() | Creation timestamp |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT now() | Last update timestamp |

**Unique Constraint:** `uq_micro_units` on (edition_id, unit_id)
**Indexes:**
- `idx_micro_units_edition` on (edition_id)
- `idx_micro_units_story_threads` GIN index on (story_threads)
- `idx_micro_units_character_dynamics` GIN index on (character_dynamics jsonb_path_ops)
- `idx_micro_units_narrative_function` on ((summary->>'narrative_function'))

**Trigger:** `trg_micro_units_updated_at` - auto-updates updated_at on modification

---

### micro_unit_members
| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| mu_pk | BIGINT | NOT NULL, FK → micro_units(mu_pk) ON DELETE CASCADE | Reference to parent micro-unit |
| edition_id | BIGINT | NOT NULL, FK → editions(edition_id) ON DELETE CASCADE | Denormalized edition reference |
| sc_id | TEXT | NOT NULL, FK → (edition_id, sc_id) in semantic_chunks | Reference to semantic chunk |
| ord | INTEGER | NOT NULL, CHECK (ord > 0) | Order within micro-unit |

**Primary Key:** (mu_pk, sc_id)
**Foreign Key:** (edition_id, sc_id) → semantic_chunks(edition_id, sc_id) ON DELETE CASCADE
**Indexes:**
- `idx_mu_members_ord` on (mu_pk, ord)
- `idx_mu_members_edition_scid` on (edition_id, sc_id)

**Trigger:** `trg_mu_member_edition_consistency` - ensures edition_id matches parent micro_unit

---

## Database Functions and Triggers

### check_member_edition_consistency()
**Purpose:** Ensures semantic_chunk_members.edition_id matches parent semantic_chunk's edition_id
**Trigger:** `trg_member_edition_consistency` on semantic_chunk_members (BEFORE INSERT OR UPDATE)

### check_mu_member_edition_consistency()
**Purpose:** Ensures micro_unit_members.edition_id matches parent micro_unit's edition_id
**Trigger:** `trg_mu_member_edition_consistency` on micro_unit_members (BEFORE INSERT OR UPDATE)

### update_timestamp()
**Purpose:** Auto-updates updated_at field to current timestamp
**Triggers:**
- `trg_semantic_chunks_updated_at` on semantic_chunks (BEFORE UPDATE)
- `trg_micro_units_updated_at` on micro_units (BEFORE UPDATE)

---
```

**Step 2: Review and verify schema documentation**

Compare the added documentation against `01_schema.sql` to ensure all tables, columns, indexes, and triggers are accurately documented.

**Step 3: Commit the enhanced AGENTS.md**

```bash
git add AGENTS.md
git commit -m "docs: enhance AGENTS.md with complete schema documentation

Add detailed table schemas, indexes, triggers, and functions from 01_schema.sql.
Agent can now reference comprehensive schema from memory instead of using
discovery tools.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Simplify query-writing Skill

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
2. **Reference schema** - Check your memory (AGENTS.md) for table structures and relationships
3. **Write the query** - Construct syntactically correct PostgreSQL query
4. **Execute** - Run with `sql_db_query` tool
5. **Format answer** - Present results clearly to the user

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
WHERE text ~* 'pattern'  -- Case-insensitive regex
WHERE text ~ 'pattern'   -- Case-sensitive regex
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
      WHERE cd->>'from' ILIKE '%character_name%'
         OR cd->>'to' ILIKE '%character_name%'
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
- Reference the Detailed Table Schemas section in AGENTS.md for exact column names and types
- Check the Useful Views section in AGENTS.md for pre-built queries
- If a query fails, read the error message carefully and check your syntax
- Use EXPLAIN to understand query performance if needed
```

**Step 2: Verify skill loads correctly**

Check that the skill file is valid YAML frontmatter and markdown:
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

Remove schema discovery workflow (now in AGENTS.md memory).
Focus on PostgreSQL syntax, query patterns, and best practices.
Reduced from 117 lines to ~50 lines.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Delete schema-exploration Skill

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

Expected output should NOT include `schema-exploration/`, only `query-writing/`

**Step 3: Commit the deletion**

```bash
git add skills/
git commit -m "remove: delete schema-exploration skill

Schema is now documented in AGENTS.md. Discovery tools will be removed,
making this skill obsolete.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Modify agent.py to Use Only Query Tool

**Files:**
- Modify: `agent.py:1-46`

**Step 1: Add import for QuerySQLDataBaseTool**

In `agent.py`, add import after line 9 (after `from langchain_community.utilities import SQLDatabase`):

```python
from langchain_community.tools.sql_database.tool import QuerySQLDataBaseTool
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
# Create only the query execution tool (no schema discovery tools)
sql_tools = [
    QuerySQLDataBaseTool(
        db=db,
        description="Execute a SQL query against the database. Returns the query results."
    )
]
```

**Step 3: Remove unused import**

Remove or comment out line 9:
```python
# from langchain_community.agent_toolkits import SQLDatabaseToolkit  # No longer needed
```

**Step 4: Verify the modified file**

Read the modified section to ensure it's correct:
```bash
sed -n '1,50p' agent.py | grep -A5 -B5 "QuerySQLDataBaseTool"
```

**Step 5: Commit the agent.py changes**

```bash
git add agent.py
git commit -m "refactor: use only query execution tool in agent

Replace SQLDatabaseToolkit with direct QuerySQLDataBaseTool creation.
Remove discovery tools (sql_db_list_tables, sql_db_schema) - schema is
now in AGENTS.md memory.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Verify Tool Availability

**Files:**
- Modify (temporarily): `agent.py:49`

**Step 1: Add debug print to verify tools**

After the `sql_tools` creation (after new line ~48), add:
```python
# Debug: verify only query tool is loaded
print(f"Available SQL tools: {[tool.name for tool in sql_tools]}")
```

**Step 2: Run agent to check tools**

```bash
python agent.py "How many works are in the database?"
```

Expected output should include:
```
Available SQL tools: ['sql_db_query']
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

## Task 6: Test Simple Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test simple single-table query**

```bash
python agent.py "How many works are in the database?"
```

Expected: Agent should successfully query the `works` table and return count without using discovery tools.

**Step 2: Verify no discovery tool usage**

Check agent output - it should NOT contain calls to:
- `sql_db_list_tables`
- `sql_db_schema`

It should ONLY use:
- `sql_db_query`

**Step 3: Document test result**

If successful, note that simple queries work. If failed, debug the error before proceeding.

---

## Task 7: Test Join Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test multi-table join query**

```bash
python agent.py "List all editions with their work titles and authors"
```

Expected: Agent should join `works` and `editions` tables using schema from AGENTS.md memory.

**Step 2: Verify agent references AGENTS.md**

Check that agent's reasoning references the schema documentation from memory, not discovery tools.

**Step 3: Document test result**

If successful, note that join queries work. If failed, debug and ensure AGENTS.md has complete foreign key information.

---

## Task 8: Test Complex JSONB Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test JSONB query**

```bash
python agent.py "Which narrative threads appear most frequently in micro units?"
```

Expected: Agent should query `micro_units.story_threads` array field using PostgreSQL array operators.

**Step 2: Verify JSONB syntax usage**

Check that agent uses correct PostgreSQL syntax for arrays (e.g., `unnest()`, `@>`, etc.).

**Step 3: Document test result**

If successful, note that JSONB queries work. If failed, verify JSONB documentation in AGENTS.md is clear.

---

## Task 9: Test Full-Text Search

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test full-text search query**

```bash
python agent.py "Find chunks containing the word 'guerre'"
```

Expected: Agent should use the GIN index with `to_tsvector` and `to_tsquery`.

**Step 2: Verify full-text search syntax**

Check that agent uses:
```sql
WHERE to_tsvector('simple', text) @@ to_tsquery('simple', 'guerre')
```

**Step 3: Document test result**

If successful, note that full-text search works. If failed, verify index documentation in AGENTS.md.

---

## Task 10: Test View Usage

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test query using pre-built views**

```bash
python agent.py "Show me a summary of the first 3 semantic chunks"
```

Expected: Agent should use `v_semantic_chunks_summary` view.

**Step 2: Verify view usage**

Check that agent queries the view instead of manually joining tables.

**Step 3: Document test result**

If successful, note that view queries work. If failed, verify view documentation in AGENTS.md.

---

## Task 11: Test Error Handling - Unauthorized Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test write operation rejection**

```bash
python agent.py "Delete all works"
```

Expected: Agent should refuse or the database should reject with permission error.

**Step 2: Verify error message is clear**

Check that user receives clear explanation that write operations are not allowed.

**Step 3: Document test result**

If successful, note that safety rules work. If agent attempts write operation, verify AGENTS.md safety rules are clear.

---

## Task 12: Test Error Handling - Invalid Query

**Files:**
- Test: `agent.py` (no modifications)

**Step 1: Test invalid table query**

```bash
python agent.py "Show me data from nonexistent_table"
```

Expected: Agent should either:
- Recognize table doesn't exist from AGENTS.md and inform user
- Execute query, get error, and explain error to user

**Step 2: Verify graceful error handling**

Check that agent provides helpful error message, not raw database error.

**Step 3: Document test result**

If successful, note that error handling works. If failed, improve error handling in agent or AGENTS.md guidance.

---

## Task 13: Final Commit and Summary

**Files:**
- None (documentation task)

**Step 1: Review all changes**

```bash
git log --oneline -10
```

Expected: Should see commits for:
1. Enhanced AGENTS.md
2. Simplified query-writing skill
3. Deleted schema-exploration skill
4. Modified agent.py
5. Various test verification commits

**Step 2: Verify success criteria**

Check all criteria from design document:
- [x] AGENTS.md contains comprehensive schema documentation
- [x] Agent has only `sql_db_query` tool
- [x] schema-exploration skill is removed
- [x] query-writing skill is simplified
- [x] All test queries execute successfully
- [x] Agent answers schema questions from memory
- [x] Clear error messages for invalid queries

**Step 3: Create summary commit (if needed)**

If any final cleanup is needed, commit it:
```bash
git add .
git commit -m "chore: finalize schema documentation implementation

All tests passing. Agent now uses documented schema from AGENTS.md
instead of runtime discovery tools.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Success Criteria

- [x] AGENTS.md enhanced with detailed table schemas, indexes, triggers, views
- [x] query-writing skill simplified to ~50 lines
- [x] schema-exploration skill deleted
- [x] agent.py uses only QuerySQLDataBaseTool
- [x] Simple query test passes
- [x] Join query test passes
- [x] JSONB query test passes
- [x] Full-text search test passes
- [x] View query test passes
- [x] Write operation rejected (safety)
- [x] Invalid query handled gracefully

## Notes

- Schema documentation in AGENTS.md must be kept in sync with 01_schema.sql manually
- If schema changes, update AGENTS.md before deploying
- Consider creating a schema validation script in the future to detect drift
