# Database Schema Documentation Design

**Date:** 2026-02-14
**Project:** Text-to-SQL Deep Agent
**Objective:** Replace runtime schema discovery with comprehensive schema documentation in AGENTS.md

## Overview

This design transitions the text-to-SQL agent from discovering database schema at runtime to referencing comprehensive schema documentation embedded in the agent's memory (AGENTS.md). This approach eliminates redundant schema discovery, simplifies the agent's skills, and improves performance.

## Architecture

### Current State

- Agent connects to PostgreSQL using `SQLDatabaseToolkit`
- Toolkit provides 3 tools: `sql_db_list_tables`, `sql_db_schema`, `sql_db_query`
- Two skills: `schema-exploration` (guides discovery) and `query-writing` (guides query construction)
- Schema discovery happens every run via tool calls

### New State

- Agent has comprehensive schema documentation in AGENTS.md (always in context via `memory=["./AGENTS.md"]`)
- Custom toolkit provides ONLY `sql_db_query` tool (no discovery tools)
- Single simplified `query-writing` skill for query best practices
- Agent references schema from memory instead of discovering it

### Key Architectural Change

The agent shifts from **runtime schema discovery** to **documented schema reference**. The schema becomes part of the agent's "knowledge" rather than something it discovers through tools.

### Rationale

Since the database schema is stable (defined in `01_schema.sql`) and comprehensive documentation is available, there's no need for the agent to rediscover it each run. This makes the agent:

- **Faster** - No time wasted on discovery tool calls
- **Simpler** - Fewer tools and skills to manage
- **More reliable** - Consistent schema reference, no discovery failures
- **More efficient** - Less context consumed by tool definitions

## Component Changes

### 1. AGENTS.md Schema Documentation

**Content Structure:**

The AGENTS.md file will be enhanced with complete schema documentation organized as follows:

#### Existing Content (Keep As-Is)
- Agent role and identity (lines 1-17)
- Current high-level table descriptions (lines 19-56)
- Query guidelines, safety rules, planning approach (lines 62-105)

#### Enhanced Schema Section

Add detailed subsections:

**a) Table Schemas**

For each table, document:
- Column names and data types
- Constraints (NOT NULL, CHECK, UNIQUE)
- Primary keys
- Foreign key relationships
- Generated/computed columns
- Purpose and usage notes

**b) Indexes**

Document important indexes:
- Full-text search index on `chunks.text`
- JSONB GIN indexes on `semantic_chunks.meta` and `micro_units` fields
- Composite indexes for joins

**c) Triggers and Functions**

Document:
- `check_member_edition_consistency()` - enforces edition_id matching in semantic_chunk_members
- `check_mu_member_edition_consistency()` - enforces edition_id matching in micro_unit_members
- `update_timestamp()` - auto-updates updated_at fields

**d) Views**

Already documented (lines 41-49), keep as-is

**Formatting Approach:**
- Use markdown tables for schema definitions
- Keep it concise but complete
- Focus on what the agent needs to write queries, not implementation details
- Estimated size: add ~150-200 lines to AGENTS.md

### 2. Code Changes in agent.py

**Current implementation (lines 44-46):**
```python
# Create SQL toolkit and get tools
toolkit = SQLDatabaseToolkit(db=db, llm=model)
sql_tools = toolkit.get_tools()
```

**New implementation (Recommended):**
```python
from langchain_community.tools.sql_database.tool import QuerySQLDataBaseTool

# Create only the query execution tool directly
sql_tools = [
    QuerySQLDataBaseTool(
        db=db,
        description="Execute a SQL query against the database. Returns the query results."
    )
]
```

**Alternative approach:**
```python
# Create SQL toolkit but only extract the query execution tool
toolkit = SQLDatabaseToolkit(db=db, llm=model)
all_tools = toolkit.get_tools()

# Filter to only keep the query execution tool
sql_tools = [tool for tool in all_tools if tool.name == "sql_db_query"]
```

**Recommendation:** Use the first approach - it's clearer and doesn't create unused tools.

**No other changes needed in agent.py:**
- DATABASE_URL still from environment variable
- Database connection logic unchanged
- Agent creation parameters unchanged (model, memory, skills, tools, backend)

### 3. Skills Changes

#### Change 1: Remove schema-exploration skill

**Action:** Delete the entire `skills/schema-exploration/` directory

**Rationale:** This skill's workflow depends on `sql_db_list_tables` and `sql_db_schema` tools which won't exist. Since the agent has comprehensive schema documentation in AGENTS.md, it can answer schema questions directly from memory.

#### Change 2: Simplify query-writing skill

**Current skill:** 117 lines with detailed workflows for simple vs complex queries, examples with specific tables, instructions to use schema tools

**Simplified skill:** ~40-50 lines focusing on:
- When to use the skill
- Basic workflow: understand question → reference schema from memory → write query → execute → format answer
- PostgreSQL-specific syntax guidelines (JSONB operators, full-text search, arrays, regex)
- Common query patterns for the literary RAG database
- Query best practices (LIMIT, aliases, CTEs, etc.)

**Key simplifications:**
- Remove schema discovery workflow instructions
- Remove specific table examples (those are in AGENTS.md)
- Focus on query syntax and PostgreSQL features
- Keep it generic and reference-oriented

## Testing and Validation

### 1. Schema Documentation Validation

- Review enhanced AGENTS.md to ensure all tables, columns, indexes, triggers, and views from `01_schema.sql` are documented
- Verify accuracy against the actual database schema
- Check that documentation is clear and usable for query writing

### 2. Code Functionality Testing

Run test queries to ensure the agent works correctly:

```bash
# Simple query - single table
python agent.py "How many works are in the database?"

# Join query - multiple tables
python agent.py "List all editions with their work titles and authors"

# Complex query - JSONB and aggregation
python agent.py "Which narrative threads appear most frequently in micro units?"

# Full-text search
python agent.py "Find chunks containing the word 'guerre'"

# View usage
python agent.py "Show me a summary of the first 3 semantic chunks"
```

### 3. Tool Availability Check

Verify the agent only has the query tool:
- Add a debug print in agent.py after creating tools: `print([tool.name for tool in sql_tools])`
- Should output: `['sql_db_query']`
- Should NOT include: `sql_db_list_tables`, `sql_db_schema`

### 4. Skill Loading Verification

- Confirm schema-exploration directory is deleted
- Confirm query-writing skill loads correctly
- Test that agent doesn't try to use discovery tools (they don't exist)

### 5. Error Handling

Test expected failures:
```bash
# Should fail gracefully - no write access
python agent.py "Delete all works"

# Should handle query errors well
python agent.py "Show me data from nonexistent_table"
```

### Expected Outcomes

- Agent answers questions using only documented schema
- No attempts to call discovery tools
- Query execution works normally
- Clear error messages when queries fail
- Faster agent initialization (fewer tools to load)

## Implementation Order

1. Enhance AGENTS.md with complete schema documentation from `01_schema.sql`
2. Simplify `skills/query-writing/SKILL.md`
3. Delete `skills/schema-exploration/` directory
4. Modify `agent.py` to create only query execution tool
5. Test with sample queries
6. Verify tool availability and error handling

## Success Criteria

- [ ] AGENTS.md contains comprehensive schema documentation (tables, indexes, triggers, views)
- [ ] Agent has only `sql_db_query` tool (no discovery tools)
- [ ] schema-exploration skill is removed
- [ ] query-writing skill is simplified (~40-50 lines)
- [ ] All test queries execute successfully
- [ ] Agent answers schema questions from memory (not tools)
- [ ] No performance degradation
- [ ] Clear error messages for invalid queries

## Future Considerations

- **Schema updates:** When `01_schema.sql` changes, manually update AGENTS.md accordingly
- **Schema validation:** Consider adding a script to compare AGENTS.md documentation against actual database schema for drift detection
- **Development mode:** If schema changes frequently during development, could add a `--discover-schema` flag to temporarily enable discovery tools

## Approved By

User approved all design sections on 2026-02-14.
