"""
Automated tests for agent configuration.
Verifies tool selection, skill existence, and architecture changes.
"""
import pytest
from pathlib import Path
import sys

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from agent import create_sql_deep_agent


def test_only_query_and_checker_tools():
    """Verify agent has only sql_db_query and sql_db_query_checker SQL tools."""
    agent = create_sql_deep_agent()

    # Extract tool names from the compiled graph's tool node
    tool_node = agent.nodes["tools"].bound
    tool_names = set(tool_node.tools_by_name.keys())

    # Should have sql_db_query and sql_db_query_checker
    assert "sql_db_query" in tool_names, \
        f"sql_db_query not found in tools: {tool_names}"
    assert "sql_db_query_checker" in tool_names, \
        f"sql_db_query_checker not found in tools: {tool_names}"

    # Should NOT have discovery tools
    assert "sql_db_list_tables" not in tool_names, \
        "Discovery tool sql_db_list_tables should not be present"
    assert "sql_db_schema" not in tool_names, \
        "Discovery tool sql_db_schema should not be present"


def test_schema_reference_skill_exists():
    """Verify schema-reference skill file exists."""
    skill_path = Path("skills/schema-reference/SKILL.md")
    assert skill_path.exists(), \
        f"schema-reference skill not found at {skill_path}"

    # Verify it has proper frontmatter
    content = skill_path.read_text()
    assert "name: schema-reference" in content, \
        "schema-reference skill missing proper frontmatter"
    assert "description:" in content, \
        "schema-reference skill missing description"


def test_schema_exploration_deleted():
    """Verify schema-exploration skill has been deleted."""
    old_skill_path = Path("skills/schema-exploration")
    assert not old_skill_path.exists(), \
        f"schema-exploration skill should be deleted, but found at {old_skill_path}"


def test_query_writing_skill_exists():
    """Verify query-writing skill exists and is updated."""
    skill_path = Path("skills/query-writing/SKILL.md")
    assert skill_path.exists(), \
        f"query-writing skill not found at {skill_path}"

    content = skill_path.read_text()

    # Should reference schema-reference skill
    assert "schema-reference" in content, \
        "query-writing skill should reference schema-reference skill"

    # Should reference sql_db_query_checker
    assert "sql_db_query_checker" in content, \
        "query-writing skill should reference sql_db_query_checker"


def test_agents_md_updated():
    """Verify AGENTS.md has been updated to remove discovery references."""
    agents_path = Path("AGENTS.md")
    assert agents_path.exists(), "AGENTS.md not found"

    content = agents_path.read_text()

    # Should reference schema-reference skill
    assert "schema-reference" in content, \
        "AGENTS.md should reference schema-reference skill"

    # Should reference sql_db_query_checker
    assert "sql_db_query_checker" in content, \
        "AGENTS.md should reference sql_db_query_checker"

    # Should NOT reference old discovery workflow
    assert "Explore the available database tables" not in content, \
        "AGENTS.md should not reference old discovery workflow"
    assert "Examine relevant table schemas" not in content, \
        "AGENTS.md should not reference old schema examination workflow"


def test_agents_md_size_unchanged():
    """Verify AGENTS.md size is approximately unchanged (~60 lines)."""
    agents_path = Path("AGENTS.md")
    line_count = len(agents_path.read_text().splitlines())

    # Allow ±10 lines variance from baseline (~60 lines)
    assert 50 <= line_count <= 70, \
        f"AGENTS.md should be ~60 lines (minimal changes), got {line_count} lines"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
