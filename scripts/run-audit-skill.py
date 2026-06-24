#!/usr/bin/env python3
"""
Execute AWS audit skills by running their bash commands directly.
Simpler and more reliable than trying to get Claude to execute them.
"""

import sys
import subprocess
import re
from pathlib import Path


def extract_bash_commands(skill_content: str) -> list[str]:
    """Extract bash commands from SKILL.md code blocks."""
    commands = []
    in_code_block = False
    current_command = []

    for line in skill_content.split('\n'):
        # Start of code block
        if line.strip().startswith('```bash') or line.strip().startswith('```sh'):
            in_code_block = True
            continue

        # End of code block
        if line.strip() == '```' and in_code_block:
            if current_command:
                commands.append('\n'.join(current_command))
                current_command = []
            in_code_block = False
            continue

        # Inside code block - collect command
        if in_code_block:
            # Skip comments
            stripped = line.strip()
            if stripped and not stripped.startswith('#'):
                current_command.append(line)

    return commands


def execute_skill(skill_path: str, output_file: str) -> int:
    """
    Execute a skill by running its bash commands.

    Args:
        skill_path: Path to SKILL.md file
        output_file: Where to write output

    Returns:
        Exit code (0 = success)
    """
    skill_file = Path(skill_path)
    if not skill_file.exists():
        print(f"Error: Skill file not found: {skill_path}", file=sys.stderr)
        return 1

    # Read skill content
    skill_content = skill_file.read_text()
    skill_name = skill_file.parent.name

    print(f"🔍 Executing skill: {skill_name}", file=sys.stderr)
    print(f"   Output: {output_file}", file=sys.stderr)

    # Extract bash commands
    commands = extract_bash_commands(skill_content)

    if not commands:
        print(f"⚠️  No bash commands found in {skill_path}", file=sys.stderr)
        # Write skill content as output for Claude to interpret
        with open(output_file, 'w') as f:
            f.write(f"=== {skill_name} ===\n\n")
            f.write("No executable commands found in skill.\n")
            f.write("Skill content:\n\n")
            f.write(skill_content)
        return 0

    print(f"   Found {len(commands)} command blocks", file=sys.stderr)

    # Execute commands and capture output
    from datetime import datetime
    audit_date = datetime.utcnow().strftime('%Y-%m-%d')
    output_lines = [f"=== {skill_name} Audit ===", f"Generated: {audit_date}", ""]

    for i, cmd in enumerate(commands, 1):
        print(f"   Executing block {i}/{len(commands)}...", file=sys.stderr)

        try:
            # Execute command
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=60,
                executable='/bin/bash'
            )

            # Capture output
            if result.stdout:
                output_lines.append(result.stdout.strip())

            if result.stderr and result.returncode != 0:
                output_lines.append(f"⚠️  Error: {result.stderr.strip()}")

        except subprocess.TimeoutExpired:
            output_lines.append(f"⏱️  Command timed out after 60s")
        except Exception as e:
            output_lines.append(f"❌ Execution error: {str(e)}")

    # Write output file
    with open(output_file, 'w') as f:
        f.write('\n'.join(output_lines))

    print(f"✅ Skill execution complete", file=sys.stderr)
    return 0


def main():
    if len(sys.argv) < 3:
        print("Usage: run-audit-skill.py <skill-path> <output-file>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  ./run-audit-skill.py .claude/skills/aws-cost-review/SKILL.md /tmp/cost-review.txt", file=sys.stderr)
        sys.exit(1)

    skill_path = sys.argv[1]
    output_file = sys.argv[2]

    exit_code = execute_skill(skill_path, output_file)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
