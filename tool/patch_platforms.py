#!/usr/bin/env python3
"""Small edits to the Android / iOS projects that `flutter create` makes.

Safe to run again: each edit is skipped when it is already there.
  - Android: internet permission (release builds need it) and the app name
  - iOS: the name under the icon
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent


def patch_android(text: str) -> str:
    if "android.permission.INTERNET" not in text:
        text = text.replace(
            "<application",
            '<uses-permission android:name="android.permission.INTERNET"/>\n    <application',
            1,
        )
    return re.sub(r'(android:label=")[^"]*(")', r"\1GoThermo\2", text, count=1)


def patch_ios(text: str) -> str:
    return re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
        r"\1GoThermo\2",
        text,
        count=1,
    )


def edit(path: pathlib.Path, fn) -> None:
    if not path.exists():
        print(f"skip (not found): {path}")
        return
    old = path.read_text(encoding="utf-8")
    new = fn(old)
    if new != old:
        path.write_text(new, encoding="utf-8")
        print(f"patched: {path.relative_to(root)}")
    else:
        print(f"already fine: {path.relative_to(root)}")


if __name__ == "__main__":
    edit(root / "android/app/src/main/AndroidManifest.xml", patch_android)
    edit(root / "ios/Runner/Info.plist", patch_ios)
    sys.exit(0)
