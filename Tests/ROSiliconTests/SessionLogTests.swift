import Foundation
import Testing
@testable import ROSilicon

struct SessionLogTests {
    @Test func writesEachSessionToTheProfileRoot() throws {
        let temp = try TemporaryDirectory()
        let log = SessionLog(root: temp.url, sessionID: "test-session")

        log.append("first line")
        log.append("second line")

        let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
        #expect(log.fileURL.path == temp.url.appending(path: "logs/test-session.log").path)
        #expect(contents.contains("first line"))
        #expect(contents.contains("second line"))
    }
}
