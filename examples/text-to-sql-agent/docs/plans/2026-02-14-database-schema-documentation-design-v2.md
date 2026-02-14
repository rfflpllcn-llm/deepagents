# Database Schema Documentation Design (Revised)

**Date:** 2026-02-14 (Revised based on feedback)
**Project:** Text-to-SQL Deep Agent
**Objective:** Replace runtime schema discovery with comprehensive schema documentation via progressive disclosure

## Overview

This design transitions the text-to-SQL agent from discovering database schema at runtime to referencing comprehensive schema documentation via a dedicated skill. This approach uses progressive disclosure (schema loaded only when invoked), keeps baseline prompt small, validates queries before execution, and eliminates redundant schema discovery.

## Architecture

### Current State

- Agent connects to PostgreSQL using `SQLDatabaseToolkit`
- Toolkit provides **4 tools**: `sql_db_list_tables`, `sql_db_schema`, `sql_db_query`, `sql_db_query_checker`
- Two skills: `schema-exploration` (guides discovery) and `query-writing` (guides query construction)
- Schema discovery happens every run via tool calls
- AGENTS.md contains references to discovery workflow (lines 8-9, 89, 97)

### New State

- Agent has comprehensive schema documentation in a new `schema-reference` skill (progressive disclosure - loaded only when invoked)
- Custom toolkit provides **2 tools**: `sql_db_query` and `sql_db_query_checker` (no discovery tools)
- Two skills: `schema-reference` (comprehensive schema docs) and `query-writing` (simplified query best practices)
- Agent invokes schema-reference skill when needed instead of discovering schema at runtime
- AGENTS.md keeps only high-level context (~40 lines), updated to reference schema-reference skill instead of discovery tools

### Key Architectural Change

The agent shifts from **runtime schema discovery** to **on-demand schema reference via skill invocation**. The schema becomes accessible through progressive disclosure (skill metadata → full content when invoked) rather than through discovery tools or always-loaded memory.

### Rationale

Since the database schema is stable (defined in `01_schema.sql`) and comprehensive documentation is available, there's no need for the agent to rediscover it each run. This makes the agent:

- **More efficient** - Smaller baseline prompt (schema loaded only when needed via progressive disclosure, not always in memory)
- **Faster** - No time wasted on discovery tool calls
- **More reliable** - Consistent schema reference, no discovery failures; query validation via `sql_db_query_checker` reduces syntax errors
- **Simpler** - Two focused tools (query + validate) instead of four mixed-purpose tools

## Component Changes

### 1. Create schema-reference Skill

**New file:** `skills/schema-reference/SKILL.md`

This skill will contain the complete schema documentation from `01_schema.sql`, making it available via progressive disclosure (loaded only when the agent needs it).

**Skill metadata:**
```yaml
---
name: schema-reference
description: Complete database schema reference - table structures, columns, indexes, triggers, and views for the literary RAG system
---
```

**Content structure:**

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

Document all available views with their purpose

**Formatting Approach:**
- Use markdown tables for schema definitions
- Keep it concise but complete
- Focus on what the agent needs to write queries, not implementation details
- Estimated size: ~200-250 lines in skill file

### 2. Update AGENTS.md

**Minimal changes to existing content:**

**Lines to update:**
- **Line 8**: Change "Explore the available database tables" → "Reference database schema via schema-reference skill"
- **Line 9**: Change "Examine relevant table schemas" → "Write syntactically correct SQL queries"
- **Line 89**: Change "List which tables you'll need to examine" → "Invoke schema-reference skill if you need detailed table information"
- **Line 97**: Change "List tables → Find chunks table → Query schema → Execute COUNT query" → "Reference schema → Write query → Execute COUNT query"

**Keep as-is:**
- High-level table descriptions (lines 19-56)
- Query guidelines, safety rules (lines 61-83)
- Views summary (lines 40-48)
- JSONB fields of interest (lines 50-55)

**Result:** AGENTS.md stays lean (~105 lines, no growth)

### 3. Code Changes in agent.py

**Current implementation (lines 44-46):**
```python
# Create SQL toolkit and get tools
toolkit = SQLDatabaseToolkit(db=db, llm=model)
sql_tools = toolkit.get_tools()  # Returns 4 tools
```

**New implementation (Recommended):**
```python
from langchain_community.tools import QuerySQLDatabaseTool, QuerySQLCheckerTool

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

**Alternative approach (filter from toolkit):**
```python
# Create SQL toolkit but only extract query and checker tools
toolkit = SQLDatabaseToolkit(db=db, llm=model)
all_tools = toolkit.get_tools()

# Filter to keep only query execution and validation tools
sql_tools = [
    tool for tool in all_tools
    if tool.name in ["sql_db_query", "sql_db_query_checker"]
]
```

**Recommendation:** Use the first approach - it's clearer, uses correct non-deprecated imports (`QuerySQLDatabaseTool` not `QuerySQLDataBaseTool`), and doesn't create unused tools.

**Import changes:**
- Remove or comment: `from langchain_community.agent_toolkits import SQLDatabaseToolkit` (if using recommended approach)
- Add: `from langchain_community.tools import QuerySQLDatabaseTool, QuerySQLCheckerTool`

**No other changes needed in agent.py:**
- DATABASE_URL still from environment variable
- Database connection logic unchanged
- Agent creation parameters unchanged (model, memory, skills, tools, backend)

### 4. Skills Changes

#### Change 1: Create schema-reference skill

**Action:** Create new directory `skills/schema-reference/` with `SKILL.md` containing complete schema documentation

**Rationale:** Progressive disclosure - schema is loaded only when the agent invokes this skill, keeping baseline prompt small. Replaces runtime discovery tools with documented reference.

#### Change 2: Remove schema-exploration skill

**Action:** Delete the entire `skills/schema-exploration/` directory

**Rationale:** This skill's workflow depends on `sql_db_list_tables` and `sql_db_schema` tools which won't exist. Replaced by schema-reference skill.

#### Change 3: Simplify query-writing skill

**Current skill:** 117 lines with detailed workflows for simple vs complex queries, examples with specific tables, instructions to use schema tools

**Simplified skill:** ~40-50 lines focusing on:
- When to use the skill
- Basic workflow: understand question → invoke schema-reference skill if needed → **validate query with sql_db_query_checker** → execute → format answer
- Reference to sql_db_query_checker tool for validation
- PostgreSQL-specific syntax guidelines (JSONB operators, full-text search, arrays, regex)
- Common query patterns for the literary RAG database
- Query best practices (LIMIT, aliases, CTEs, etc.)

**Key simplifications:**
- Remove schema discovery workflow instructions (replaced with "invoke schema-reference skill")
- Remove specific table examples (those are in schema-reference skill)
- **Add query validation step using sql_db_query_checker**
- Focus on query syntax and PostgreSQL features

## Testing and Validation

### 1. Schema Documentation Validation

- Review new schema-reference skill to ensure all tables, columns, indexes, triggers, and views from `01_schema.sql` are documented
- Verify accuracy against the actual database schema
- Check that documentation is clear and usable for query writing
- Verify skill metadata (name, description) is correct

### 2. Code Functionality Testing

Run test queries to ensure the agent works correctly:

```bash
# Simple query - single table
uv run python agent.py "How many works are in the database?"

# Join query - multiple tables
uv run python agent.py "List all editions with their work titles and authors"

# Complex query - JSONB and aggregation
uv run python agent.py "Which narrative threads appear most frequently in micro units?"

# Full-text search
uv run python agent.py "Find chunks containing the word 'guerre'"

# View usage
uv run python agent.py "Show me a summary of the first 3 semantic chunks"
```

### 3. Tool Availability Check

Verify the agent has only query and checker tools:
- Add a debug print in agent.py after creating tools: `print([tool.name for tool in sql_tools])`
- Should output: `['sql_db_query', 'sql_db_query_checker']`
- Should NOT include: `sql_db_list_tables`, `sql_db_schema`

### 4. Skill Loading Verification

- Confirm schema-reference skill exists and loads correctly
- Confirm schema-exploration directory is deleted
- Confirm query-writing skill loads correctly
- **Test that agent invokes schema-reference skill when it needs schema details**
- Test that agent doesn't try to use discovery tools (they don't exist)

### 5. Error Handling

Test expected failures:
```bash
# Should fail gracefully - no write access
uv run python agent.py "Delete all works"

# Should handle query errors well
uv run python agent.py "Show me data from nonexistent_table"

# Query checker should catch syntax errors
uv run python agent.py "Show me data where syntax is invalid SQL"
```

### Expected Outcomes

- **Agent invokes schema-reference skill when needed (not always loaded)** - progressive disclosure working
- No attempts to call discovery tools
- **Query validation catches syntax errors before execution** - sql_db_query_checker working
- Query execution works normally
- Clear error messages when queries fail
- **Smaller baseline prompt (schema loaded on-demand, not in AGENTS.md)**

## Implementation Order

1. Create `skills/schema-reference/SKILL.md` with complete schema documentation from `01_schema.sql`
2. Update `AGENTS.md` to remove discovery tool references (lines 8-9, 89, 97)
3. Simplify `skills/query-writing/SKILL.md` to reference schema-reference skill and query checker
4. Delete `skills/schema-exploration/` directory
5. Modify `agent.py` to create query execution and validation tools (not discovery tools), use correct imports
6. Test with sample queries (using `uv run`)
7. Verify tool availability, skill invocation, and error handling

## Success Criteria

- [ ] schema-reference skill contains comprehensive schema documentation (tables, indexes, triggers, views)
- [ ] AGENTS.md updated to remove discovery tool references, keeps high-level context only (~105 lines, no growth)
- [ ] Agent has `sql_db_query` and `sql_db_query_checker` tools (no discovery tools)
- [ ] schema-exploration skill is removed
- [ ] query-writing skill is simplified (~40-50 lines) and references schema-reference skill
- [ ] All test queries execute successfully (using `uv run`)
- [ ] Agent invokes schema-reference skill when needed (progressive disclosure working)
- [ ] Query checker validates syntax before execution
- [ ] Smaller baseline prompt (schema not always loaded)
- [ ] Clear error messages for invalid queries
- [ ] Correct imports used (`QuerySQLDatabaseTool` not deprecated `QuerySQLDataBaseTool`)

## Future Considerations

- **Schema updates:** When `01_schema.sql` changes, manually update schema-reference skill accordingly
- **Schema validation:** Consider adding a script to compare schema-reference skill documentation against actual database schema for drift detection
- **Development mode:** If schema changes frequently during development, could add a `--discover-schema` flag to temporarily enable discovery tools
- **Performance monitoring:** Track baseline prompt size before/after to confirm progressive disclosure benefits

## Design Decisions (Documented from Feedback)

**Question 1: Keep sql_db_query_checker?**
- **Decision:** Keep it (Option A)
- **Rationale:** Validates SQL syntax before execution, reduces malformed query risk and wasted tokens on failed executions

**Question 2: Schema location?**
- **Decision:** Schema in skill (Option B)
- **Rationale:** Progressive disclosure keeps baseline prompt small. Skills are metadata-first, content loaded on-demand. AGENTS.md is always loaded, so adding 150-200 lines increases baseline cost.

## Approved By

User approved all design sections on 2026-02-14.
User provided feedback and approved revised architecture on 2026-02-14.
