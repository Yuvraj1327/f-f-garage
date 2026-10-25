"""Tests for configure_platforms.py. Run from mobile/:  python3 -m unittest discover -s tool"""

import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import configure_platforms as cp  # noqa: E402

MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="ff_garage"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity" android:exported="true">
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
"""
GRADLE_KTS = """android {
    namespace = "com.example.ff_garage"
    defaultConfig {
        applicationId = "com.example.ff_garage"
        minSdk = flutter.minSdkVersion
    }
}
"""
GRADLE_GROOVY = """android {
    defaultConfig {
        applicationId "com.example.ff_garage"
        minSdkVersion flutter.minSdkVersion
    }
}
"""
PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleName</key>
\t<string>ff_garage</string>
</dict>
</plist>
"""
DELEGATE = """import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
"""
PODFILE = "# Uncomment this line to define a global platform for your project\n# platform :ios, '12.0'\n"
INDEX = "<!DOCTYPE html>\n<html>\n<head>\n  <title>ff_garage</title>\n</head>\n<body></body>\n</html>\n"

ENV = """API_BASE_URL=http://x
GOOGLE_CLIENT_ID_IOS=123-abc.apps.googleusercontent.com
GOOGLE_MAPS_KEY_ANDROID=AndroidKey123
GOOGLE_MAPS_KEY_IOS=IosKey456
GOOGLE_MAPS_KEY_WEB=WebKey789
"""


def make_project(root: Path, gradle: str = GRADLE_KTS, gradle_name: str = "build.gradle.kts") -> None:
    (root / "pubspec.yaml").write_text("name: ff_garage\n")
    (root / ".env").write_text(ENV)
    files = {
        "android/app/src/main/AndroidManifest.xml": MANIFEST,
        f"android/app/{gradle_name}": gradle,
        "android/local.properties": "sdk.dir=/sdk\n",
        "ios/Runner/Info.plist": PLIST,
        "ios/Runner/AppDelegate.swift": DELEGATE,
        "ios/Podfile": PODFILE,
        "ios/Flutter/Debug.xcconfig": '#include "Generated.xcconfig"\n',
        "ios/Flutter/Release.xcconfig": '#include "Generated.xcconfig"\n',
        "web/index.html": INDEX,
    }
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)


def run(root: Path, *extra: str) -> str:
    out = io.StringIO()
    with redirect_stdout(out):
        code = cp.main(["--root", str(root), *extra])
    assert code == 0, out.getvalue()
    return out.getvalue()


class ConfigureTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        make_project(self.root)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def read(self, name: str) -> str:
        return (self.root / name).read_text()

    def test_android_gets_a_placeholder_and_the_key_goes_to_local_properties(self) -> None:
        run(self.root)
        manifest = self.read("android/app/src/main/AndroidManifest.xml")
        self.assertIn('android:name="com.google.android.geo.API_KEY"', manifest)
        self.assertIn("${MAPS_API_KEY}", manifest)
        self.assertNotIn("AndroidKey123", manifest)
        for permission in cp.ANDROID_PERMISSIONS:
            self.assertIn(permission, manifest)
        # The meta-data sits inside <application>.
        self.assertLess(manifest.index("<application"), manifest.index("geo.API_KEY"))
        self.assertLess(manifest.index("geo.API_KEY"), manifest.index("</application>"))
        gradle = self.read("android/app/build.gradle.kts")
        self.assertIn('manifestPlaceholders["MAPS_API_KEY"]', gradle)
        self.assertNotIn("AndroidKey123", gradle)
        props = self.read("android/local.properties")
        self.assertIn("sdk.dir=/sdk", props)  # Flutter's own line is kept
        self.assertIn("MAPS_API_KEY=AndroidKey123", props)

    def test_groovy_gradle_is_supported_too(self) -> None:
        self._tmp.cleanup()
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        make_project(self.root, GRADLE_GROOVY, "build.gradle")
        run(self.root)
        gradle = self.read("android/app/build.gradle")
        self.assertIn("manifestPlaceholders += [MAPS_API_KEY:", gradle)

    def test_ios_gets_references_and_the_secrets_file(self) -> None:
        run(self.root)
        plist = self.read("ios/Runner/Info.plist")
        self.assertIn("$(GOOGLE_MAPS_API_KEY)", plist)
        self.assertIn("$(GOOGLE_IOS_REVERSED_CLIENT_ID)", plist)
        self.assertIn("NSLocationWhenInUseUsageDescription", plist)
        self.assertNotIn("IosKey456", plist)
        self.assertTrue(plist.rstrip().endswith("</plist>"))
        secrets = self.read("ios/Flutter/Secrets.xcconfig")
        self.assertIn("GOOGLE_MAPS_API_KEY=IosKey456", secrets)
        self.assertIn("GOOGLE_IOS_REVERSED_CLIENT_ID=com.googleusercontent.apps.123-abc", secrets)
        for name in ("Debug", "Release"):
            self.assertIn('#include? "Secrets.xcconfig"', self.read(f"ios/Flutter/{name}.xcconfig"))
        delegate = self.read("ios/Runner/AppDelegate.swift")
        self.assertIn("import GoogleMaps", delegate)
        self.assertLess(
            delegate.index("GMSServices.provideAPIKey"),
            delegate.index("GeneratedPluginRegistrant.register"),
        )
        self.assertNotIn("IosKey456", delegate)
        self.assertIn("platform :ios, '14.0'", self.read("ios/Podfile"))
        self.assertNotIn("# platform", self.read("ios/Podfile"))

    def test_web_loads_the_script_from_a_git_ignored_config(self) -> None:
        run(self.root)
        index = self.read("web/index.html")
        self.assertIn("maps_config.js", index)
        self.assertIn("maps.googleapis.com/maps/api/js", index)
        self.assertNotIn("WebKey789", index)
        self.assertLess(index.index("maps_config.js"), index.index("</head>"))
        self.assertIn("window.GOOGLE_MAPS_KEY_WEB = 'WebKey789';", self.read("web/maps_config.js"))

    def test_running_twice_changes_nothing_the_second_time(self) -> None:
        run(self.root)
        snapshot = {
            str(p.relative_to(self.root)): p.read_text()
            for p in self.root.rglob("*")
            if p.is_file()
        }
        second = run(self.root)
        after = {
            str(p.relative_to(self.root)): p.read_text()
            for p in self.root.rglob("*")
            if p.is_file()
        }
        self.assertEqual(snapshot, after)
        self.assertNotIn("done:", second)

    def test_changing_a_key_updates_only_the_ignored_files(self) -> None:
        run(self.root)
        committed = {
            n: self.read(n)
            for n in (
                "android/app/src/main/AndroidManifest.xml",
                "android/app/build.gradle.kts",
                "ios/Runner/Info.plist",
                "ios/Runner/AppDelegate.swift",
                "web/index.html",
            )
        }
        (self.root / ".env").write_text(ENV.replace("AndroidKey123", "NewAndroid"))
        run(self.root)
        self.assertIn("MAPS_API_KEY=NewAndroid", self.read("android/local.properties"))
        for name, text in committed.items():
            self.assertEqual(text, self.read(name), name)

    def test_check_mode_writes_nothing(self) -> None:
        before = {p: p.read_text() for p in self.root.rglob("*") if p.is_file()}
        output = run(self.root, "--check")
        after = {p: p.read_text() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(before, after)
        self.assertIn("would:", output)

    def test_placeholders_and_empty_keys_warn_and_never_print_values(self) -> None:
        (self.root / ".env").write_text(
            "GOOGLE_MAPS_KEY_ANDROID=YOUR-ANDROID-MAPS-KEY\nGOOGLE_MAPS_KEY_WEB=RealWebKeyXYZ\n"
        )
        output = run(self.root)
        self.assertIn("GOOGLE_MAPS_KEY_ANDROID is empty", output)
        self.assertIn("GOOGLE_MAPS_KEY_IOS is empty", output)
        self.assertIn("GOOGLE_CLIENT_ID_IOS is empty", output)
        self.assertNotIn("RealWebKeyXYZ", output)
        self.assertIn("MAPS_API_KEY=\n", self.read("android/local.properties"))

    def test_a_file_that_looks_unfamiliar_is_left_alone_with_a_warning(self) -> None:
        odd = "this is not a manifest"
        (self.root / "android/app/src/main/AndroidManifest.xml").write_text(odd)
        output = run(self.root)
        self.assertIn("WARN:  AndroidManifest.xml", output)
        self.assertEqual(odd, self.read("android/app/src/main/AndroidManifest.xml"))

    def test_missing_platform_folders_are_skipped(self) -> None:
        import shutil

        shutil.rmtree(self.root / "ios")
        shutil.rmtree(self.root / "web")
        output = run(self.root)
        self.assertIn("skip:  ios/ not found", output)
        self.assertIn("skip:  web/ not found", output)

    def test_existing_url_types_get_the_google_scheme_added(self) -> None:
        plist = PLIST.replace(
            "</dict>\n</plist>",
            "\t<key>CFBundleURLTypes</key>\n\t<array>\n\t\t<dict>\n\t\t\t<key>CFBundleURLSchemes</key>\n"
            "\t\t\t<array><string>myapp</string></array>\n\t\t</dict>\n\t</array>\n</dict>\n</plist>",
        )
        (self.root / "ios/Runner/Info.plist").write_text(plist)
        run(self.root)
        text = self.read("ios/Runner/Info.plist")
        self.assertEqual(text.count("<key>CFBundleURLTypes</key>"), 1)
        self.assertIn("myapp", text)
        self.assertIn("$(GOOGLE_IOS_REVERSED_CLIENT_ID)", text)

    def test_a_single_quote_in_a_key_cannot_break_the_js_file(self) -> None:
        (self.root / ".env").write_text("GOOGLE_MAPS_KEY_WEB=ab'cd\n")
        run(self.root)
        self.assertIn("'ab\\'cd'", self.read("web/maps_config.js"))

    def test_reversed_client_id(self) -> None:
        self.assertEqual(
            cp.reversed_client_id("1-x.apps.googleusercontent.com"),
            "com.googleusercontent.apps.1-x",
        )
        self.assertEqual(cp.reversed_client_id("nonsense"), "")


if __name__ == "__main__":
    unittest.main()
