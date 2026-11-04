import Foundation
import Testing

@testable import Snowdrop

@Suite("UpdaterService")
struct UpdaterServiceTests {
    @Test("Strips release- and v prefixes from tags")
    func versionFromTag() {
        #expect(UpdaterService.version(fromTag: "release-v1.2.1") == "1.2.1")
        #expect(UpdaterService.version(fromTag: "v1.2") == "1.2")
        #expect(UpdaterService.version(fromTag: "1.0") == "1.0")
    }

    @Test("Compares versions numerically")
    func isNewer() {
        #expect(UpdaterService.isNewer("1.10", than: "1.9"))
        #expect(UpdaterService.isNewer("1.2.1", than: "1.2"))
        #expect(!UpdaterService.isNewer("1.2.0", than: "1.2"))
        #expect(!UpdaterService.isNewer("1.1.9", than: "1.2"))
    }

    @Test("Parses the latest release and picks the DMG asset")
    func parsesRelease() throws {
        let json = """
        {"tag_name": "release-v1.3", "draft": false, "prerelease": false,
         "html_url": "https://github.com/example/repo/releases/tag/release-v1.3", "body": "Notes",
         "assets": [
           {"name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt"},
           {"name": "Snowdrop-v1.3.dmg", "browser_download_url": "https://example.com/Snowdrop-v1.3.dmg"}
         ]}
        """
        let info = try #require(UpdaterService.parseRelease(Data(json.utf8)))
        #expect(info.version == "1.3")
        #expect(info.notes == "Notes")
        #expect(info.downloadURL.lastPathComponent == "Snowdrop-v1.3.dmg")
    }

    @Test("Ignores prereleases and releases without a DMG")
    func rejectsUnusable() {
        let prerelease = #"{"tag_name": "v2", "prerelease": true, "html_url": "https://example.com", "assets": [{"name": "a.dmg", "browser_download_url": "https://example.com/a.dmg"}]}"#
        #expect(UpdaterService.parseRelease(Data(prerelease.utf8)) == nil)
        let noDMG = #"{"tag_name": "v2", "html_url": "https://example.com", "assets": []}"#
        #expect(UpdaterService.parseRelease(Data(noDMG.utf8)) == nil)
    }
}
