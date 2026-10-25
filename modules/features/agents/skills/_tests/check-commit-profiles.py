import pathlib
import sys
import tomllib

source, standard, fine, artifacts = map(pathlib.Path, sys.argv[1:])
base = (standard / "SKILL.md").read_text()
variant = (fine / "SKILL.md").read_text()
assert base == (source / "SKILL.md").read_text(), "standard skill changed"
assert variant != base, "fine-grained profile was not rendered"

# The shared workflow, including staging and publication rules, must stay intact.
for text in (base, variant):
    assert "\nname: commit\n" in text
assert base.split("## Arguments", 1)[1].split("\n2. ", 1)[0] == variant.split(
    "## Arguments", 1
)[1].split("\n2. ", 1)[0]
assert base.split("\n3. ", 1)[1] == variant.split("\n3. ", 1)[1]
assert "smallest independently revertible units" not in variant
assert "include both sides and update references" not in variant
assert "Creates atomic" not in variant
assert len(variant.splitlines()) < 150
assert (standard / "SKILL.md.license").read_bytes() == (
    fine / "SKILL.md.license"
).read_bytes()

for profile, chosen in (("standard", standard), ("fine-grained", fine)):
    root = artifacts / profile
    assert (root / ".claude/skills/commit").resolve() == chosen
    settings = tomllib.loads((root / "codex-override").read_text())
    entries = settings["skills"]["config"]
    assert {entry["path"] for entry in entries} == {
        str(standard / "SKILL.md"),
        str(fine / "SKILL.md"),
    }
    assert [entry["path"] for entry in entries if entry["enabled"]] == [
        str(chosen / "SKILL.md")
    ]
