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
SELECT unnest(story_threads) AS thread FROM micro_units LIMIT 10
```

**Regex matching:**
```sql
WHERE text ~* 'pattern'  -- Case-insensitive
WHERE text ~ 'pattern'   -- Case-sensitive
```

**Type casting:**
```sql
SELECT year::text, count(*)::integer FROM editions GROUP BY year LIMIT 5
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
SELECT unit_id, sc_id, chunk_text FROM mu_content LIMIT 5;
```

**Search in JSONB arrays:**
```sql
-- Find micro-units involving a specific character
SELECT
    unit_id,
    summary->>'what_happens' AS what_happens
FROM micro_units
WHERE edition_id = 1
  AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(character_dynamics) cd
      WHERE cd->>'from' ILIKE '%character%'
         OR cd->>'to' ILIKE '%character%'
  )
ORDER BY page_start
LIMIT 5;
```

**Use pre-built views:**
```sql
-- Semantic chunk summaries
SELECT sc_id, page_start, page_end, word_count
FROM v_semantic_chunks_summary
WHERE edition_id = 1
LIMIT 5;

-- Micro-unit summaries
SELECT unit_id, what_happens, narrative_function
FROM v_micro_units_summary
WHERE edition_id = 1
LIMIT 5;

-- Character interactions
SELECT character_from, character_to, relation_type, interaction
FROM v_character_interactions
WHERE character_from ILIKE '%name%'
LIMIT 5;

-- Story thread participation
SELECT unit_id, page_start, what_happens
FROM v_story_thread_units
WHERE story_thread = 'thread_name'
LIMIT 5;
```

## Tips

- For complex analytical questions, break down your thinking before writing the query
- Invoke schema-reference skill for detailed table structures and column names
- Use sql_db_query_checker to validate syntax before executing
- Check pre-built views (v_semantic_chunks_summary, v_micro_units_summary, etc.) for common lookups
- If a query fails, read the error message carefully and check your syntax
