#!/usr/bin/env python3
"""
Execute a Claude Code skill via AWS Bedrock.

Reads a SKILL.md file, invokes Claude via Bedrock to interpret and execute
the audit commands, and returns structured output.
"""

import json
import sys
import subprocess
import os
from pathlib import Path

try:
    import boto3
except ImportError:
    print("Error: boto3 not installed. Installing...", file=sys.stderr)
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "boto3"])
    import boto3


def invoke_claude_bedrock(skill_content: str, skill_name: str, aws_region: str = "us-west-2") -> str:
    """
    Invoke Claude via AWS Bedrock to execute a skill.

    Args:
        skill_content: The full SKILL.md content
        skill_name: Name of the skill (for context)
        aws_region: AWS region for Bedrock

    Returns:
        Claude's response (audit output)
    """
    bedrock = boto3.client("bedrock-runtime", region_name=aws_region)

    # Construct prompt for Claude
    system_prompt = """You are an AWS infrastructure auditor executing automated audit skills.

Your task:
1. Read the provided skill document (SKILL.md format)
2. Execute each AWS CLI command in the workflow
3. Analyze the output
4. Return a structured audit report

IMPORTANT:
- Execute commands using subprocess, don't just describe them
- Handle errors gracefully (some commands may fail - that's OK)
- Return actual data from AWS, not example/placeholder values
- Format output clearly with sections and findings
- Flag critical issues prominently (🔴 for critical, ⚠️ for warnings)"""

    user_prompt = f"""Execute this AWS audit skill:

# Skill: {skill_name}

{skill_content}

---

Execute the audit workflow described above. Run each AWS CLI command, capture output, and generate the structured report format shown in the skill.

If a command fails with AccessDenied, note it in your output (we'll auto-detect missing permissions later).

Return the complete audit report."""

    # Prepare request for Claude 3.5 Sonnet
    request_body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 8000,
        "system": system_prompt,
        "messages": [
            {
                "role": "user",
                "content": user_prompt
            }
        ],
        "temperature": 0.3  # Lower temperature for consistent, factual output
    }

    # Invoke Bedrock
    try:
        response = bedrock.invoke_model(
            modelId="anthropic.claude-3-5-sonnet-20241022-v2:0",
            body=json.dumps(request_body)
        )

        response_body = json.loads(response["body"].read())

        # Extract text from response
        if "content" in response_body and len(response_body["content"]) > 0:
            return response_body["content"][0]["text"]
        else:
            return f"Error: Unexpected response format from Bedrock\n{json.dumps(response_body, indent=2)}"

    except Exception as e:
        return f"Error invoking Bedrock: {str(e)}\n\nThis may indicate:\n1. Bedrock not enabled in this region\n2. Missing bedrock:InvokeModel permission\n3. Model not available"


def main():
    if len(sys.argv) < 2:
        print("Usage: run-skill-via-bedrock.py <path-to-skill.md> [aws-region]", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  ./run-skill-via-bedrock.py .claude/skills/aws-cost-review/SKILL.md", file=sys.stderr)
        sys.exit(1)

    skill_path = Path(sys.argv[1])
    aws_region = sys.argv[2] if len(sys.argv) > 2 else "us-west-2"

    if not skill_path.exists():
        print(f"Error: Skill file not found: {skill_path}", file=sys.stderr)
        sys.exit(1)

    # Read skill content
    skill_content = skill_path.read_text()
    skill_name = skill_path.parent.name

    print(f"🤖 Invoking Claude via Bedrock to execute skill: {skill_name}", file=sys.stderr)
    print(f"   Region: {aws_region}", file=sys.stderr)
    print(f"   Model: anthropic.claude-3-5-sonnet-20241022-v2:0", file=sys.stderr)
    print("", file=sys.stderr)

    # Invoke Claude
    result = invoke_claude_bedrock(skill_content, skill_name, aws_region)

    # Output result to stdout (will be captured by workflow)
    print(result)

    print("", file=sys.stderr)
    print("✅ Skill execution complete", file=sys.stderr)


if __name__ == "__main__":
    main()
