#!/usr/bin/env python3
"""Puts the Google Maps keys and Google sign-in settings from mobile/.env into the
native platform folders that `flutter create` generates (android/, ios/, web/).

Run it from the mobile/ folder, after `flutter create --platforms=android,ios,web .`
and again whenever you change the Google values in .env:

    python3 tool/configure_platforms.py            # patch
    python3 tool/configure_platforms.py --check    # report only, change nothing

Why a script: the keys must not be committed. They are written to files that are
git-ignored (android/local.properties, ios/Flutter/Secrets.xcconfig,
web/maps_config.js) and the committed files only refer to them by name
(${MAPS_API_KEY}, $(GOOGLE_MAPS_API_KEY), window.GOOGLE_MAPS_KEY_WEB).

Safe to re-run (each patch is applied once). If a generated file looks different
from what this script expects it says so and leaves the file alone; the README
shows the same change to make by hand. Key values are never printed.
Standard library only.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

PLACEHOLDER = re.compile(r"^(YOUR[-_]|your_)", re.IGNORECASE)

# --------------------------------------------------------------------------- helpers


def read_env(path: Path) -> dict[str, str]:
    """KEY=value lines of a .env file. Placeholders from .env.example read as empty."""
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        values[key.strip()] = "" if PLACEHOLDER.match(value) else value
    return values


def reversed_client_id(client_id: str) -> str:
    """'123-abc.apps.googleusercontent.com' -> 'com.googleusercontent.apps.123-abc'."""
    suffix = ".apps.googleusercontent.com"
    if client_id.endswith(suffix):
        return "com.googleusercontent.apps." + client_id[: -len(suffix)]
    return ""


def set_property(text: str, key: str, value: str, comment: str = "#") -> str:
    """Set KEY=value in a properties-style file, replacing an existing line."""
    line = f"{key}={value}"
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    if pattern.search(text):
        return pattern.sub(lambda _m: line, text)
    if text and not text.endswith("\n"):
        text += "\n"
    return text + line + "\n"


class Report:
    def __init__(self, check_only: bool) -> None:
        self.check_only = check_only
        self.lines: list[str] = []
        self.problems = 0

    def done(self, message: str) -> None:
        self.lines.append(("would: " if self.check_only else "done:  ") + message)

    def ok(self, message: str) -> None:
        self.lines.append("ok:    " + message)

    def skip(self, message: str) -> None:
        self.lines.append("skip:  " + message)

    def warn(self, message: str) -> None:
        self.problems += 1
        self.lines.append("WARN:  " + message)

    def write(self, path: Path, text: str, what: str) -> None:
        if path.exists() and path.read_text(encoding="utf-8") == text:
            self.ok(f"{what} already up to date")
            return
        if not self.check_only:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
        self.done(what)


# --------------------------------------------------------------------------- Android

MAPS_META = (
    '        <meta-data android:name="com.google.android.geo.API_KEY"\n'
    '            android:value="${MAPS_API_KEY}"/>\n'
)
ANDROID_PERMISSIONS = (
    "android.permission.INTERNET",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
)

KTS_BLOCK = (
    "        // Maps key comes from android/local.properties (git-ignored), written by\n"
    "        // tool/configure_platforms.py from mobile/.env.\n"
    "        val mapsProperties = java.util.Properties()\n"
    '        rootProject.file("local.properties").takeIf { it.exists() }\n'
    "            ?.inputStream()?.use { mapsProperties.load(it) }\n"
    '        manifestPlaceholders["MAPS_API_KEY"] =\n'
    '            mapsProperties.getProperty("MAPS_API_KEY", "")\n'
)
GROOVY_BLOCK = (
    "        // Maps key comes from android/local.properties (git-ignored), written by\n"
    "        // tool/configure_platforms.py from mobile/.env.\n"
    "        def mapsProperties = new Properties()\n"
    "        def mapsPropertiesFile = rootProject.file('local.properties')\n"
    "        if (mapsPropertiesFile.exists()) {\n"
    "            mapsPropertiesFile.withInputStream { mapsProperties.load(it) }\n"
    "        }\n"
    "        manifestPlaceholders += [MAPS_API_KEY: mapsProperties.getProperty('MAPS_API_KEY', '')]\n"
)


def patch_manifest(text: str) -> tuple[str, list[str]]:
    """Add the permissions and the Maps meta-data. Returns (text, what changed)."""
    changed: list[str] = []
    application = re.search(r"<application\b[^>]*?(?<!/)>", text, re.DOTALL)
    if application is None:
        raise ValueError("no <application> element")
    if "com.google.android.geo.API_KEY" not in text:
        end = application.end()
        text = text[:end] + "\n" + MAPS_META.rstrip("\n") + text[end:]
        changed.append("Maps meta-data")
    missing = [p for p in ANDROID_PERMISSIONS if p not in text]
    if missing:
        start = re.search(r"<application\b", text).start()
        line_start = text.rfind("\n", 0, start) + 1
        block = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in missing)
        text = text[:line_start] + block + text[line_start:]
        changed.append("permissions " + ", ".join(p.split(".")[-1] for p in missing))
    return text, changed


def patch_gradle(text: str, kotlin: bool) -> tuple[str, bool]:
    if "MAPS_API_KEY" in text:
        return text, False
    match = re.search(r"^[ \t]*defaultConfig\s*\{[ \t]*\n", text, re.MULTILINE)
    if match is None:
        raise ValueError("no defaultConfig block")
    block = KTS_BLOCK if kotlin else GROOVY_BLOCK
    return text[: match.end()] + block + text[match.end() :], True


def configure_android(root: Path, env: dict[str, str], report: Report) -> None:
    android = root / "android"
    if not android.is_dir():
        report.skip("android/ not found (run `flutter create --platforms=android .` first)")
        return
    key = env.get("GOOGLE_MAPS_KEY_ANDROID", "")
    props = android / "local.properties"
    current = props.read_text(encoding="utf-8") if props.exists() else ""
    report.write(props, set_property(current, "MAPS_API_KEY", key), "android/local.properties (Maps key)")
    if not key:
        report.warn("GOOGLE_MAPS_KEY_ANDROID is empty: Android maps stay switched off")

    manifest = android / "app/src/main/AndroidManifest.xml"
    if manifest.exists():
        try:
            patched, changed = patch_manifest(manifest.read_text(encoding="utf-8"))
        except ValueError as error:
            report.warn(f"AndroidManifest.xml: {error}; add the meta-data by hand (README)")
        else:
            if changed:
                report.write(manifest, patched, "AndroidManifest.xml: " + "; ".join(changed))
            else:
                report.ok("AndroidManifest.xml already patched")
    else:
        report.warn("android/app/src/main/AndroidManifest.xml not found")

    for name, kotlin in (("build.gradle.kts", True), ("build.gradle", False)):
        gradle = android / "app" / name
        if not gradle.exists():
            continue
        try:
            patched, changed = patch_gradle(gradle.read_text(encoding="utf-8"), kotlin)
        except ValueError as error:
            report.warn(f"app/{name}: {error}; add the placeholder by hand (README)")
        else:
            if changed:
                report.write(gradle, patched, f"app/{name}: manifestPlaceholders for the Maps key")
            else:
                report.ok(f"app/{name} already patched")
        break
    else:
        report.warn("android/app/build.gradle(.kts) not found")


# --------------------------------------------------------------------------- iOS

INFO_PLIST_KEYS = """\
\t<key>GMSApiKey</key>
\t<string>$(GOOGLE_MAPS_API_KEY)</string>
\t<key>GIDClientID</key>
\t<string>$(GOOGLE_IOS_CLIENT_ID)</string>
\t<key>NSLocationWhenInUseUsageDescription</key>
\t<string>F&amp;F Garage uses your location to pin where we should come for your service.</string>
"""
URL_TYPES = """\
\t<key>CFBundleURLTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleTypeRole</key>
\t\t\t<string>Editor</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array>
\t\t\t\t<string>$(GOOGLE_IOS_REVERSED_CLIENT_ID)</string>
\t\t\t</array>
\t\t</dict>
\t</array>
"""
URL_TYPE_ENTRY = """\
\t\t<dict>
\t\t\t<key>CFBundleTypeRole</key>
\t\t\t<string>Editor</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array>
\t\t\t\t<string>$(GOOGLE_IOS_REVERSED_CLIENT_ID)</string>
\t\t\t</array>
\t\t</dict>
"""


def patch_info_plist(text: str) -> tuple[str, list[str]]:
    changed: list[str] = []
    if "GMSApiKey" not in text:
        index = text.rfind("</dict>")
        if index < 0:
            raise ValueError("no closing </dict>")
        keys = INFO_PLIST_KEYS
        if "NSLocationWhenInUseUsageDescription" in text:
            keys = "".join(keys.splitlines(keepends=True)[:4])  # keep the existing text
        text = text[:index] + keys + text[index:]
        changed.append("GMSApiKey, GIDClientID, location text")
    if "GOOGLE_IOS_REVERSED_CLIENT_ID" not in text:
        if "<key>CFBundleURLTypes</key>" in text:
            match = re.search(r"<key>CFBundleURLTypes</key>\s*<array>\s*\n", text)
            if match is None:
                raise ValueError("unexpected CFBundleURLTypes layout")
            text = text[: match.end()] + URL_TYPE_ENTRY + text[match.end() :]
        else:
            index = text.rfind("</dict>")
            text = text[:index] + URL_TYPES + text[index:]
        changed.append("Google sign-in URL scheme")
    return text, changed


def patch_app_delegate(text: str) -> tuple[str, bool]:
    if "GMSServices.provideAPIKey" in text:
        return text, False
    register = re.search(r"^([ \t]*)GeneratedPluginRegistrant\.register\(", text, re.MULTILINE)
    if register is None or "import Flutter" not in text:
        raise ValueError("unexpected AppDelegate.swift layout")
    indent = register.group(1)
    # Only when a key is set: the SDK dislikes an empty one, and without a key the
    # app does not show maps anyway.
    provide = (
        f'{indent}if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,\n'
        f'{indent}  !mapsKey.isEmpty {{\n'
        f'{indent}  GMSServices.provideAPIKey(mapsKey)\n'
        f'{indent}}}\n'
    )
    text = text[: register.start()] + provide + text[register.start() :]
    return text.replace("import Flutter\n", "import Flutter\nimport GoogleMaps\n", 1), True


def patch_podfile(text: str) -> tuple[str, bool]:
    wanted = "platform :ios, '14.0'"
    match = re.search(r"^[ \t]*#?[ \t]*platform :ios, '(\d+)(?:\.\d+)?'[ \t]*$", text, re.MULTILINE)
    if match is None:
        raise ValueError("no platform line")
    line = match.group(0)
    if not line.lstrip().startswith("#") and int(match.group(1)) >= 14:
        return text, False
    return text.replace(line, wanted, 1), True


def configure_ios(root: Path, env: dict[str, str], report: Report) -> None:
    ios = root / "ios"
    if not ios.is_dir():
        report.skip("ios/ not found (run `flutter create --platforms=ios .` first)")
        return
    maps_key = env.get("GOOGLE_MAPS_KEY_IOS", "")
    client = env.get("GOOGLE_CLIENT_ID_IOS", "")
    secrets = ios / "Flutter/Secrets.xcconfig"
    text = (
        "// Written by tool/configure_platforms.py from mobile/.env. Git-ignored.\n"
        f"GOOGLE_MAPS_API_KEY={maps_key}\n"
        f"GOOGLE_IOS_CLIENT_ID={client}\n"
        f"GOOGLE_IOS_REVERSED_CLIENT_ID={reversed_client_id(client)}\n"
    )
    report.write(secrets, text, "ios/Flutter/Secrets.xcconfig (Maps key, iOS client ID)")
    if not maps_key:
        report.warn("GOOGLE_MAPS_KEY_IOS is empty: iOS maps stay switched off")
    if not client:
        report.warn("GOOGLE_CLIENT_ID_IOS is empty: Google sign-in is off on iOS")

    include = '#include? "Secrets.xcconfig"\n'
    for name in ("Debug.xcconfig", "Release.xcconfig", "Profile.xcconfig"):
        path = ios / "Flutter" / name
        if not path.exists():
            continue
        content = path.read_text(encoding="utf-8")
        if "Secrets.xcconfig" in content:
            report.ok(f"{name} already includes Secrets.xcconfig")
        else:
            report.write(path, content.rstrip("\n") + "\n" + include, f"{name}: include Secrets.xcconfig")

    plist = ios / "Runner/Info.plist"
    if plist.exists():
        try:
            patched, changed = patch_info_plist(plist.read_text(encoding="utf-8"))
        except ValueError as error:
            report.warn(f"Info.plist: {error}; add the keys by hand (README)")
        else:
            if changed:
                report.write(plist, patched, "Info.plist: " + "; ".join(changed))
            else:
                report.ok("Info.plist already patched")
    else:
        report.warn("ios/Runner/Info.plist not found")

    delegate = ios / "Runner/AppDelegate.swift"
    if delegate.exists():
        try:
            patched, changed = patch_app_delegate(delegate.read_text(encoding="utf-8"))
        except ValueError as error:
            report.warn(f"AppDelegate.swift: {error}; add GMSServices.provideAPIKey by hand (README)")
        else:
            if changed:
                report.write(delegate, patched, "AppDelegate.swift: provide the Maps key")
            else:
                report.ok("AppDelegate.swift already patched")
    else:
        report.warn("ios/Runner/AppDelegate.swift not found")

    podfile = ios / "Podfile"
    if podfile.exists():
        try:
            patched, changed = patch_podfile(podfile.read_text(encoding="utf-8"))
        except ValueError as error:
            report.warn(f"Podfile: {error}; set `platform :ios, '14.0'` by hand")
        else:
            if changed:
                report.write(podfile, patched, "Podfile: iOS 14 (needed by the Maps SDK)")
            else:
                report.ok("Podfile platform already iOS 14 or newer")
    else:
        report.skip("ios/Podfile not found yet (it is created by the first `flutter build ios`)")


# --------------------------------------------------------------------------- Web

WEB_SNIPPET = """\
  <!-- Google Maps: the key is read from maps_config.js (git-ignored, written by
       tool/configure_platforms.py). The script is loaded here, before Flutter
       starts, because the map plugin expects window.google.maps to exist. -->
  <script src="maps_config.js"></script>
  <script>
    if (window.GOOGLE_MAPS_KEY_WEB) {
      document.write('<script src="https://maps.googleapis.com/maps/api/js?key=' +
        encodeURIComponent(window.GOOGLE_MAPS_KEY_WEB) + '"><\\/script>');
    }
  </script>
"""


def patch_index_html(text: str) -> tuple[str, bool]:
    if "GOOGLE_MAPS_KEY_WEB" in text:
        return text, False
    index = text.find("</head>")
    if index < 0:
        raise ValueError("no </head>")
    return text[:index] + WEB_SNIPPET + text[index:], True


def configure_web(root: Path, env: dict[str, str], report: Report) -> None:
    web = root / "web"
    if not web.is_dir():
        report.skip("web/ not found (run `flutter create --platforms=web .` first)")
        return
    key = env.get("GOOGLE_MAPS_KEY_WEB", "")
    escaped = key.replace("\\", "\\\\").replace("'", "\\'")
    config = (
        "// Written by tool/configure_platforms.py from mobile/.env. Git-ignored.\n"
        f"window.GOOGLE_MAPS_KEY_WEB = '{escaped}';\n"
    )
    report.write(web / "maps_config.js", config, "web/maps_config.js (Maps key)")
    if not key:
        report.warn("GOOGLE_MAPS_KEY_WEB is empty: web maps stay switched off")
    index = web / "index.html"
    if not index.exists():
        report.warn("web/index.html not found")
        return
    try:
        patched, changed = patch_index_html(index.read_text(encoding="utf-8"))
    except ValueError as error:
        report.warn(f"index.html: {error}; add the script by hand (README)")
        return
    if changed:
        report.write(index, patched, "web/index.html: load the Maps script")
    else:
        report.ok("web/index.html already patched")


# --------------------------------------------------------------------------- main


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", default=".", help="the Flutter project (default: current folder)")
    parser.add_argument("--env", default=None, help="the .env file (default: <root>/.env)")
    parser.add_argument("--check", action="store_true", help="report only, change nothing")
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    if not (root / "pubspec.yaml").exists():
        print(f"{root} is not a Flutter project (no pubspec.yaml). Run this from mobile/.")
        return 2
    env_path = Path(args.env) if args.env else root / ".env"
    if not env_path.exists():
        print(f"{env_path} not found. Create it first: cp .env.example .env")
        return 2
    env = read_env(env_path)

    report = Report(args.check)
    configure_android(root, env, report)
    configure_ios(root, env, report)
    configure_web(root, env, report)
    print("\n".join(report.lines))
    if report.problems:
        print(f"\n{report.problems} warning(s). Maps / sign-in that depend on them stay off until fixed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
