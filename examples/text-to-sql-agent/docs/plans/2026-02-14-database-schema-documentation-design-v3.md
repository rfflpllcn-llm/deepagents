# Database Schema Documentation Design (v3 - Final)

**Date:** 2026-02-14 (Final revision based on comprehensive feedback)
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
- AGENTS.md contains references to discovery workflow (lines 8-9, 89, 97), currently ~105 lines

### New State

- Agent has comprehensive schema documentation in a new `schema-reference` skill (progressive disclosure - loaded only when invoked)
- Custom toolkit provides **2 tools**: `sql_db_query` and `sql_db_query_checker` (no discovery tools)
- Two skills: `schema-reference` (comprehensive schema docs) and `query-writing` (simplified query best practices)
- Agent invokes schema-reference skill when needed instead of discovering schema at runtime
- AGENTS.md keeps only high-level context (~105 lines), updated to reference schema-reference skill and query checker instead of discovery tools

### Key Architectural Change

The agent shifts from **runtime schema discovery** to **on-demand schema reference via skill invocation**. The schema becomes accessible through progressive disclosure (skill metadata → full content when invoked) rather than through discovery tools or always-loaded memory.

### Rationale

Since the database schema is stable (defined in `01_schema.sql`) and comprehensive documentation is available, there's no need for the agent to rediscover it each run. This makes the agent:

- **More efficient** - Smaller baseline prompt (schema loaded only when needed via progressive disclosure, not always in memory)
- **Faster** - No time wasted on discovery tool calls
- **More reliable** - Consistent schema reference, no discovery failures; query validation via `sql_db_query_checker` reduces syntax errors
- **Simpler** - Two focused tools (query + validate) instead of four mixed-purpose tools
- **More testable** - Automated tests verify tool selection behavior, preventing regressions

## Component Changes

### 1. Create schema-reference Skill

**New file:** `skills/schema-reference/SKILL.md`

This skill contains the complete schema documentation from `01_schema.sql`, making it available via progressive disclosure (loaded only when the agent needs it).

**Skill metadata:**
```yaml
---
name: schema-reference
description: Complete database schema reference - table structures, columns, indexes, triggers, and views for the literary RAG system
---
```

**Content structure:**

**a) Table Schemas** - For each table, document: column names, data types, constraints, primary keys, foreign keys, generated columns, purpose

**b) Indexes** - Document: full-text search indexes, JSONB GIN indexes, composite indexes for joins

**c) Triggers and Functions** - Document: consistency checkers, timestamp updaters

**d) Views** - Document all pre-built views with their purpose

**e) Query Tips** - Document PostgreSQL-specific syntax (JSONB operators, full-text search, arrays, regex)

**Estimated size:** ~200-250 lines

### 2. Update AGENTS.md

**Minimal changes to existing content:**

**Update "Your Role" section (lines 7-12) to 6-step workflow:**

From:
```markdown
1. Explore the available database tables
2. Examine relevant table schemas
3. Generate syntactically correct SQL queries
4. Execute queries and analyze results
5. Format answers in a clear, readable way
```

To:
```markdown
1. Reference database schema via schema-reference skill when needed
2. Write syntactically correct SQL queries
3. Validate queries with sql_db_query_checker
4. Execute queries and analyze results
5. Format answers in a clear, readable way
```

**Update line 89:** "Invoke schema-reference skill if you need detailed table information"

**Update line 97:** "Reference schema → Write query → Validate → Execute COUNT query"

**Result:** AGENTS.md stays at ~105 lines (minimal changes, no growth)

### 3. Code Changes in agent.py

**Current implementation (lines 44-46):**
```python
toolkit = SQLDatabaseToolkit(db=db, llm=model)
sql_tools = toolkit.get_tools()  # Returns 4 tools
```

**New implementation:**
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

**Import changes:**
- Remove or comment: `from langchain_community.agent_toolkits import SQLDatabaseToolkit`
- Add: `from langchain_community.tools import QuerySQLDatabaseTool, QuerySQLCheckerTool`

**Note:** Uses correct non-deprecated imports (`QuerySQLDatabaseTool` not `QuerySQLDataBaseTool`)

### 4. Skills Changes

#### Change 1: Create schema-reference skill

**Action:** Create `skills/schema-reference/SKILL.md` with complete schema documentation from `01_schema.sql`

**Rationale:** Progressive disclosure - schema loaded only when invoked, keeps baseline prompt small

#### Change 2: Remove schema-exploration skill

**Action:** Delete entire `skills/schema-exploration/` directory

**Rationale:** Replaced by schema-reference skill; discovery tools no longer exist

#### Change 3: Simplify query-writing skill

**Current:** 117 lines with schema discovery workflow

**New:** ~65 lines focusing on:
- Workflow: understand → invoke schema-reference if needed → write → validate → execute → format
- PostgreSQL syntax guidelines (JSONB, full-text, arrays, regex)
- Common query patterns
- Query best practices

**Key fixes:**
- Remove schema discovery instructions
- Add validation step using sql_db_query_checker
- **Fix examples: no SELECT *, all queries have LIMIT**
- Reference schema-reference skill for details

### 5. Automated Testing

**New file:** `tests/test_agent_configuration.py`

**6 automated tests:**
1. `test_only_query_and_checker_tools` - Verify exact 2 tools present, no discovery tools
2. `test_schema_reference_skill_exists` - Verify new skill exists with proper frontmatter
3. `test_schema_exploration_deleted` - Verify old skill removed
4. `test_query_writing_skill_exists` - Verify skill updated with references
5. `test_agents_md_updated` - Verify AGENTS.md references new skill/tool
6. `test_agents_md_size_unchanged` - Verify ~105 lines (100-110 range)

**Rationale:** Automated regression protection for tool selection behavior, addressing the high-risk gap of manual-only validation

## Testing and Validation

### Automated Tests

```bash
uv run pytest tests/test_agent_configuration.py -v
```

Expected: 6/6 tests passing

### Manual Functional Tests

```bash
# Simple query
uv run python agent.py "How many works are in the database?"

# Join query
uv run python agent.py "List all editions with their work titles and authors"

# JSONB query
uv run python agent.py "Which narrative threads appear most frequently in micro units?"

# Full-text search
uv run python agent.py "Find chunks containing the word 'guerre'"

# View usage
uv run python agent.py "Show me a summary of the first 3 semantic chunks"

# Error handling - unauthorized
uv run python agent.py "Delete all works"

# Error handling - invalid syntax
uv run python agent.py "Show me data where syntax is invalid"

# Error handling - invalid table
uv run python agent.py "Show me data from nonexistent_table"
```

### Expected Outcomes

- Agent invokes schema-reference skill when needed (progressive disclosure working)
- No attempts to call discovery tools
- Query checker validates syntax before execution
- Query execution works normally
- Clear error messages when queries fail
- Baseline prompt size unchanged (~105 lines)
- All automated tests pass

## Implementation Order

1. Create `skills/schema-reference/SKILL.md` with complete schema
2. Update `AGENTS.md` to 6-step workflow, reference new skill/tool (lines 8-9, 89, 97)
3. Simplify `skills/query-writing/SKILL.md`, fix examples (no SELECT *, add LIMIT)
4. Delete `skills/schema-exploration/` directory
5. Modify `agent.py` to use QuerySQLDatabaseTool and QuerySQLCheckerTool
6. Create `tests/test_agent_configuration.py` with 6 automated tests
7. Run automated tests to verify configuration
8. Run manual functional tests
9. Verify baseline prompt size unchanged

## Success Criteria

- [ ] schema-reference skill contains comprehensive schema (tables, indexes, triggers, views)
- [ ] AGENTS.md updated with 6-step workflow, ~105 lines (unchanged)
- [ ] Agent has exactly 2 tools: `sql_db_query` and `sql_db_query_checker`
- [ ] schema-exploration skill deleted
- [ ] query-writing skill simplified (~65 lines), examples fixed (no SELECT *, all have LIMIT)
- [ ] Correct imports used (QuerySQLDatabaseTool not deprecated version)
- [ ] Automated tests created (6 tests)
- [ ] All automated tests pass (6/6)
- [ ] All manual functional tests pass
- [ ] Agent invokes schema-reference skill when needed (progressive disclosure)
- [ ] Query checker validates syntax before execution
- [ ] Baseline prompt size confirmed (~105 lines)
- [ ] Clear error messages for invalid queries

## Design Decisions (From Feedback)

**Feedback Round 1:**
- Q1: Keep sql_db_query_checker? **A: Yes** - validates syntax, reduces wasted tokens
- Q2: Schema location? **A: In skill** - progressive disclosure, smaller baseline prompt

**Feedback Round 2:**
- Tool count correction: 4 tools → 2 tools (not 3)
- Import fix: Use `QuerySQLDatabaseTool` (not deprecated `QuerySQLDataBaseTool`)
- Command format: Use `uv run python` (not bare `python`)
- AGENTS.md line 9 conflict: Resolved - use 6-step workflow with explicit validation
- Missing automated tests: Added comprehensive test suite (6 tests)
- Success criteria pre-checked: Fixed - all unmarked `[ ]` for implementation
- query-writing examples contradictions: Fixed - no SELECT *, all have LIMIT
- Size claims inconsistency: Fixed - consistently ~105 lines

## Future Considerations

- **Schema updates:** Manually update `skills/schema-reference/SKILL.md` when `01_schema.sql` changes
- **Schema validation:** Consider script to detect drift between skill and actual schema
- **Development mode:** Could add `--discover-schema` flag to temporarily enable discovery tools
- **Performance monitoring:** Track baseline prompt size before/after to confirm benefits
- **Test expansion:** Add integration tests for schema-reference skill invocation patterns

## Approved By

- User approved initial design sections: 2026-02-14
- User approved revised architecture (v2): 2026-02-14
- User approved final fixes (v3): 2026-02-14
