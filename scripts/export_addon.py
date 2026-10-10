#!/usr/bin/env python3
"""
GDLua Export & Addon Packaging Script
Packages compiled GDExtension binaries and configuration into a standard Godot addon format.
Generates:
  - dist/addons/gdlua/   (drop into project's addons/ directory)
  - dist/gdlua.zip       (extract into project root directly)
"""

import os
import sys
import shutil
import zipfile
from pathlib import Path

# Platform directory to binary extension mapping
BINARY_EXTENSIONS = {
    "windows": [".dll"],
    "linux": [".so"],
    "macos": [".dylib", ".framework"],
    "android": [".so"],
    "ios": [".dylib", ".a", ".framework"],
    "web": [".wasm"],
}

def package_addon():
    root_dir = Path(__file__).resolve().parent.parent
    project_bin = root_dir / "project" / "bin"
    dist_dir = root_dir / "dist"
    addon_dir = dist_dir / "addons" / "gdlua"
    zip_path = dist_dir / "gdlua.zip"

    print("========================================")
    print("       GDLua Addon Export Script        ")
    print("========================================")

    if not project_bin.exists():
        print(f"Error: Could not find '{project_bin}'. Build the project first.")
        sys.exit(1)

    # 1. Clean previous dist
    if dist_dir.exists():
        print(f"Cleaning previous export at {dist_dir}...")
        shutil.rmtree(dist_dir)

    addon_dir.mkdir(parents=True, exist_ok=True)

    # 2. Copy gdlua.gdextension
    gdext_src = project_bin / "gdlua.gdextension"
    if not gdext_src.exists():
        print(f"Error: Could not find '{gdext_src}'.")
        sys.exit(1)

    shutil.copy2(gdext_src, addon_dir / "gdlua.gdextension")
    print(f"  [OK] Copied gdlua.gdextension")

    # 3. Copy platform binaries (filtering out .exp, .lib, .pdb, and temporary files)
    copied_binaries = 0
    for platform_dir in project_bin.iterdir():
        if not platform_dir.is_dir():
            continue

        platform_name = platform_dir.name.lower()
        allowed_exts = BINARY_EXTENSIONS.get(platform_name, [".dll", ".so", ".dylib", ".wasm"])

        dest_platform_dir = addon_dir / platform_name

        for file_path in platform_dir.iterdir():
            # Skip non-files, temporary lock files (~*), and build metadata (.lib, .exp, .pdb, .gitkeep)
            if not file_path.is_file():
                continue
            if file_path.name.startswith("~") or file_path.name.startswith("."):
                continue
            if file_path.suffix.lower() not in allowed_exts:
                continue

            dest_platform_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file_path, dest_platform_dir / file_path.name)
            copied_binaries += 1
            file_size_kb = file_path.stat().st_size / 1024
            print(f"  [OK] Included [{platform_name}] {file_path.name} ({file_size_kb:.1f} KB)")

    if copied_binaries == 0:
        print("Warning: No compiled binaries found! Run scons to compile first.")

    # 4. Add a clean README inside the addon
    readme_content = """# GDLua Godot Addon

High-performance, secure, and sandboxed Lua 5.5 integration for Godot 4.1+.

## Installation
Drop this `addons/gdlua/` folder into your Godot project.

## Usage
In GDScript:
```gdscript
var lua := GDLua.new()
lua.compile("score = 100")
lua.run()
print(lua.get_global("score")) # 100
```
"""
    (addon_dir / "README.md").write_text(readme_content, encoding="utf-8")

    # 5. Create zip distribution archive
    print(f"\nCreating ZIP archive: {zip_path.name}...")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zip_file:
        for file_path in dist_dir.rglob("*"):
            if file_path == zip_path or file_path.is_dir():
                continue
            arcname = file_path.relative_to(dist_dir)
            zip_file.write(file_path, arcname)

    zip_size_kb = zip_path.stat().st_size / 1024
    print(f"  [OK] Successfully created {zip_path.name} ({zip_size_kb:.1f} KB)")

    print("\n========================================")
    print("           Export Completed!            ")
    print("========================================")
    print(f"Export directory: {addon_dir}")
    print(f"Export ZIP:       {zip_path}")
    print("\nHow to install in any future project:")
    print("  * Option 1: Extract 'gdlua.zip' into your project's root directory.")
    print("  * Option 2: Copy 'addons/gdlua' into your project's 'addons/' folder.")

if __name__ == "__main__":
    package_addon()
