#!/usr/bin/env python3
"""Migrate class declarations from old (params) syntax to new { fields } syntax (D061 Phase B)."""

import re
import sys
import os


def find_class_paren_section(line):
    """Find the (params) section of a class declaration.
    Returns (before_paren, params_str, after_paren) or None."""
    m = re.match(r'^(\s*)class\s+', line)
    if not m:
        return None

    pos = m.end()

    # Skip class name
    while pos < len(line) and (line[pos].isalnum() or line[pos] == '_'):
        pos += 1

    # Skip generic params <...> (handle nested <> for constraints like <T extends A & B>)
    if pos < len(line) and line[pos] == '<':
        depth = 1
        pos += 1
        while pos < len(line) and depth > 0:
            if line[pos] == '<':
                depth += 1
            elif line[pos] == '>':
                depth -= 1
            pos += 1

    # Skip whitespace
    while pos < len(line) and line[pos] == ' ':
        pos += 1

    # Skip 'extends ParentName<...>' if present
    if pos < len(line) and line[pos:].startswith('extends '):
        pos += 8
        while pos < len(line) and (line[pos].isalnum() or line[pos] == '_'):
            pos += 1
        if pos < len(line) and line[pos] == '<':
            depth = 1
            pos += 1
            while pos < len(line) and depth > 0:
                if line[pos] == '<':
                    depth += 1
                elif line[pos] == '>':
                    depth -= 1
                pos += 1

    # Skip whitespace
    while pos < len(line) and line[pos] == ' ':
        pos += 1

    # Must be at '(' for old syntax
    if pos >= len(line) or line[pos] != '(':
        return None

    # Find matching ')'
    paren_start = pos
    depth = 1
    pos += 1
    while pos < len(line) and depth > 0:
        if line[pos] == '(':
            depth += 1
        elif line[pos] == ')':
            depth -= 1
        pos += 1

    before_paren = line[:paren_start]
    params_str = line[paren_start + 1 : pos - 1]
    after_paren = line[pos:]

    return (before_paren, params_str, after_paren.rstrip())


def parse_params(params_str):
    """Parse comma-separated field params, handling generic types like Map<K,V>."""
    params_str = params_str.strip()
    if not params_str:
        return []

    params = []
    depth = 0
    current = ""
    for ch in params_str:
        if ch == '<':
            depth += 1
            current += ch
        elif ch == '>':
            depth -= 1
            current += ch
        elif ch == ',' and depth == 0:
            params.append(current.strip())
            current = ""
        else:
            current += ch
    if current.strip():
        params.append(current.strip())

    return params


def transform_file(filepath, dry_run=False):
    """Transform all old-style class declarations in a file.
    Returns (changed, details) where details lists each transformation."""
    with open(filepath, 'r') as f:
        lines = f.readlines()

    new_lines = []
    changed = False
    details = []

    for i, line in enumerate(lines):
        stripped = line.rstrip('\n').rstrip('\r')

        result = find_class_paren_section(stripped)
        if result is None:
            new_lines.append(line)
            continue

        before_paren, params_str, after_paren = result
        params = parse_params(params_str)

        # Determine leading whitespace
        m = re.match(r'^(\s*)', stripped)
        leading = m.group(1) if m else ""
        indent = leading + "    "

        # Parse after_paren for interface clause and opening brace
        after = after_paren.strip()
        has_brace = after.endswith('{')

        if has_brace:
            interface_part = after[:-1].strip()
        else:
            interface_part = after.strip()

        # Build class header
        class_header = before_paren.strip()
        if interface_part:
            class_header += " " + interface_part

        if len(params) == 0:
            if has_brace:
                new_lines.append(leading + class_header + " {\n")
            else:
                new_lines.append(leading + class_header + " {}\n")
        else:
            new_lines.append(leading + class_header + " {\n")
            for param in params:
                new_lines.append(indent + param + "\n")

            if has_brace:
                new_lines.append("\n")
            else:
                new_lines.append(leading + "}\n")

        changed = True
        details.append(f"  L{i+1}: {stripped.strip()}")

    if changed and not dry_run:
        with open(filepath, 'w') as f:
            f.writelines(new_lines)

    return changed, details


def find_files(directory, pattern=r'\.ss$'):
    """Find all .ss files in directory recursively."""
    matches = []
    for root, dirs, files in os.walk(directory):
        for fname in sorted(files):
            if re.search(pattern, fname):
                matches.append(os.path.join(root, fname))
    return matches


def main():
    dry_run = '--dry-run' in sys.argv
    dirs = [d for d in sys.argv[1:] if d != '--dry-run']

    if not dirs:
        print("Usage: migrate_class_syntax.py [--dry-run] <dir1> [dir2] ...")
        sys.exit(1)

    total_files = 0
    total_classes = 0

    for d in dirs:
        files = find_files(d)
        for filepath in files:
            changed, details = transform_file(filepath, dry_run=dry_run)
            if changed:
                total_files += 1
                total_classes += len(details)
                rel = os.path.relpath(filepath)
                print(f"{'[DRY] ' if dry_run else ''}Migrated {rel} ({len(details)} classes)")
                for detail in details:
                    print(detail)

    mode = "Would migrate" if dry_run else "Migrated"
    print(f"\n{mode}: {total_classes} classes in {total_files} files")


if __name__ == '__main__':
    main()
