#!/usr/bin/env python3
"""Updates image.tag in a Helm values file."""
import re
import sys


def update_image_tag(values_file: str, tag: str) -> None:
    with open(values_file, "r") as f:
        content = f.read()

    if re.search(r"^image:\s*$", content, re.MULTILINE):
        # Replace the tag line that sits under the existing image: block
        content = re.sub(
            r"(^image:\s*\n\s+tag:)\s*\S+",
            rf"\g<1> {tag}",
            content,
            flags=re.MULTILINE,
        )
    else:
        # No image: block yet — append one
        content = content.rstrip("\n") + f"\nimage:\n  tag: {tag}\n"

    with open(values_file, "w") as f:
        f.write(content)

    print(f"Updated image.tag to {tag} in {values_file}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <values-file> <tag>", file=sys.stderr)
        sys.exit(1)
    update_image_tag(sys.argv[1], sys.argv[2])
