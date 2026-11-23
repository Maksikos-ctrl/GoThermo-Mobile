#!/usr/bin/env python3
"""Small edits to the Android / iOS projects that `flutter create` makes.

Safe to run again: each edit is skipped when it is already there.
  - Android: internet permission (release builds need it) and the app name
  - iOS: the name under the icon, photo / camera texts, and (when the
    GOOGLE_IOS_CLIENT_ID environment variable is set) the Google sign-in URL scheme
"""
import os
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


def add_key(text: str, key: str, value_xml: str) -> str:
    if f"<key>{key}</key>" in text:
        return text
    return text.replace("</dict>\n</plist>", f"\t<key>{key}</key>\n\t{value_xml}\n</dict>\n</plist>", 1)


def patch_ios(text: str) -> str:
    text = re.sub(
        r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)",
        r"\1GoThermo\2",
        text,
        count=1,
    )
    text = add_key(text, "NSPhotoLibraryUsageDescription",
                   "<string>Choose pictures to send and to use as your profile picture.</string>")
    text = add_key(text, "NSCameraUsageDescription",
                   "<string>Take a photo to send in a chat.</string>")
    client = os.environ.get("GOOGLE_IOS_CLIENT_ID", "").strip()
    if client.endswith(".apps.googleusercontent.com") and "GIDClientID" not in text:
        reversed_id = "com.googleusercontent.apps." + client[: -len(".apps.googleusercontent.com")]
        text = add_key(text, "GIDClientID", f"<string>{client}</string>")
        text = add_key(
            text,
            "CFBundleURLTypes",
            "<array><dict><key>CFBundleURLSchemes</key><array>"
            f"<string>{reversed_id}</string></array></dict></array>",
        )
    return text


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
