#!/usr/bin/env python3
"""Small edits to the Android / iOS projects that `flutter create` makes.

Safe to run again: each edit is skipped when it is already there.
  - Android: internet, microphone, camera and audio permissions (calls) and the app name
  - iOS: the name under the icon, photo / camera / microphone texts, and (when the
    GOOGLE_IOS_CLIENT_ID environment variable is set) the Google sign-in URL scheme
"""
import os
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent


ANDROID_PERMISSIONS = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
    '<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
    '<uses-feature android:name="android.hardware.microphone" android:required="false"/>',
]


def patch_android(text: str) -> str:
    for line in ANDROID_PERMISSIONS:
        name = re.search(r'android:name="([^"]+)"', line).group(1)
        if f'android:name="{name}"' not in text:
            text = text.replace("<application", line + "\n    <application", 1)
    return re.sub(r'(android:label=")[^"]*(")', r"\1GoThermo\2", text, count=1)


def patch_gradle(text: str) -> str:
    """flutter_local_notifications needs core library desugaring on Android."""
    if "coreLibraryDesugaring" in text:
        return text
    if "compileOptions {" in text:
        flag = "isCoreLibraryDesugaringEnabled = true" if ".kts" in text[:0] or "compileSdk = " in text else "coreLibraryDesugaringEnabled true"
        text = text.replace("compileOptions {", "compileOptions {\n        " + flag, 1)
    dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if "compileSdk = " in text else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
    if "dependencies {" in text:
        text = text.replace("dependencies {", "dependencies {\n    " + dep, 1)
    else:
        text += "\ndependencies {\n    " + dep + "\n}\n"
    return text


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
                   "<string>Take a photo to send in a chat, or show yourself in a video call.</string>")
    text = add_key(text, "NSMicrophoneUsageDescription",
                   "<string>The microphone is used for voice and video calls.</string>")
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


MAC_ENTITLEMENTS = [
    "com.apple.security.network.client",
    "com.apple.security.device.audio-input",
    "com.apple.security.device.camera",
]


def patch_macos_entitlements(text: str) -> str:
    for key in MAC_ENTITLEMENTS:
        if f"<key>{key}</key>" not in text:
            text = text.replace("</dict>\n</plist>", f"\t<key>{key}</key>\n\t<true/>\n</dict>\n</plist>", 1)
    return text


def patch_macos_info(text: str) -> str:
    text = add_key(text, "NSMicrophoneUsageDescription",
                   "<string>The microphone is used for voice and video calls.</string>")
    return add_key(text, "NSCameraUsageDescription",
                   "<string>The camera is used for video calls.</string>")


if __name__ == "__main__":
    edit(root / "android/app/src/main/AndroidManifest.xml", patch_android)
    for name in ("build.gradle.kts", "build.gradle"):
        if (root / "android/app" / name).exists():
            edit(root / "android/app" / name, patch_gradle)
            break
    edit(root / "ios/Runner/Info.plist", patch_ios)
    edit(root / "macos/Runner/DebugProfile.entitlements", patch_macos_entitlements)
    edit(root / "macos/Runner/Release.entitlements", patch_macos_entitlements)
    edit(root / "macos/Runner/Info.plist", patch_macos_info)
    sys.exit(0)
