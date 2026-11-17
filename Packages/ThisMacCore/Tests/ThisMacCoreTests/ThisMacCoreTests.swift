import XCTest
@testable import ThisMacCore

/// Test double: moves "trashed" items into a private folder instead of the user's real Trash.
final class FolderTrasher: Trasher, @unchecked Sendable {
    let folder: URL
    var trashed: [URL] = []
    var shouldFail = false

    init(folder: URL) { self.folder = folder }

    func trash(_ url: URL) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        let target = folder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        trashed.append(target)
    }
}

class TempFolderTestCase: XCTestCase {
    var root: URL!
    var trasher: FolderTrasher!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appendingPathComponent("ThisMacCoreTests-" + UUID().uuidString)
            .resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let trashFolder = root.appendingPathComponent("__trash")
        try fm.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        trasher = FolderTrasher(folder: trashFolder)
    }

    override func tearDownWithError() throws {
        // Restore permissions so removal works after the permission test.
        _ = try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("locked").path)
        try? fm.removeItem(at: root)
    }

    @discardableResult
    func makeFile(_ path: String, _ content: String = "x") throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func makeFolder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }
}

final class DirectoryListerTests: TempFolderTestCase {
    let lister = DirectoryLister()

    func testFoldersComeFirstAndNamesSortNaturally() throws {
        let work = try makeFolder("work")
        try makeFile("work/file10.txt")
        try makeFile("work/file2.txt")
        try makeFile("work/alpha.txt")
        try makeFolder("work/zeta")
        try makeFolder("work/beta")

        let names = try lister.list(work, showHidden: false).map(\.name)

        XCTAssertEqual(names, ["beta", "zeta", "alpha.txt", "file2.txt", "file10.txt"])
    }

    func testHiddenItemsAreListedOnlyWhenAsked() throws {
        let work = try makeFolder("work")
        try makeFile("work/.secret")
        try makeFile("work/shown.txt")

        XCTAssertEqual(try lister.list(work, showHidden: false).map(\.name), ["shown.txt"])
        XCTAssertEqual(try lister.list(work, showHidden: true).map(\.name), [".secret", "shown.txt"])
    }

    func testPackageIsAnItemNotAFolder() throws {
        let work = try makeFolder("work")
        try makeFolder("work/Sample.app/Contents")

        let entry = try XCTUnwrap(lister.list(work, showHidden: false).first)

        XCTAssertTrue(entry.isPackage)
        XCTAssertFalse(entry.isFolder)
    }

    func testSymlinkToFolderIsAFolder() throws {
        let work = try makeFolder("work")
        let real = try makeFolder("real")
        try fm.createSymbolicLink(at: work.appendingPathComponent("link"), withDestinationURL: real)

        let entry = try XCTUnwrap(lister.list(work, showHidden: false).first)

        XCTAssertTrue(entry.isFolder)
        XCTAssertTrue(entry.isSymlink)
    }

    func testSystemFoldersAtDriveRootAreHiddenItems() throws {
        let rootURL = URL(fileURLWithPath: "/")
        let all = try lister.list(rootURL, showHidden: true)
        let visible = try lister.list(rootURL, showHidden: false).map(\.name)

        XCTAssertEqual(all.first { $0.name == "usr" }?.isHidden, true)
        XCTAssertEqual(all.first { $0.name == "private" }?.isHidden, true)
        XCTAssertFalse(visible.contains("usr"))
        XCTAssertTrue(visible.contains("Users"))
        XCTAssertTrue(visible.contains("Applications"))
    }

    func testUnreadableFolderThrowsInsteadOfLookingEmpty() throws {
        let locked = try makeFolder("locked")
        try makeFile("locked/inside.txt")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        XCTAssertThrowsError(try lister.list(locked, showHidden: false))
    }

    func testSortBySizeDescendingKeepsFoldersFirst() throws {
        let work = try makeFolder("work")
        try makeFile("work/small.txt", "1")
        try makeFile("work/big.txt", String(repeating: "1", count: 500))
        try makeFolder("work/folder")

        let entries = try lister.list(work, showHidden: false)
        let names = DirectoryLister.sorted(entries, by: .size, ascending: false).map(\.name)

        XCTAssertEqual(names, ["folder", "big.txt", "small.txt"])
    }
}

final class DateSortTests: TempFolderTestCase {
    func testSortByDateMixesFoldersWithOtherItemsNewestFirst() throws {
        let work = try makeFolder("work")
        let old = try makeFile("work/old.txt")
        let folder = try makeFolder("work/middle")
        let new = try makeFile("work/new.txt")
        let day: TimeInterval = 86_400
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3 * day)], ofItemAtPath: old.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * day)], ofItemAtPath: folder.path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -1 * day)], ofItemAtPath: new.path)

        let entries = try DirectoryLister().list(work, showHidden: false)
        let names = DirectoryLister.sorted(entries, by: .modified, ascending: false).map(\.name)

        XCTAssertEqual(names, ["new.txt", "middle", "old.txt"])
    }

    func testItemsKnowWhenTheyWereAdded() throws {
        let work = try makeFolder("work")
        try makeFile("work/a.txt")

        let entry = try XCTUnwrap(DirectoryLister().list(work, showHidden: false).first)

        XCTAssertNotNil(entry.added)
    }
}

final class FileOperationsTests: TempFolderTestCase {
    var ops: FileOperations!

    override func setUpWithError() throws {
        try super.setUpWithError()
        ops = FileOperations(trasher: trasher)
    }

    func failOnConflict(_ url: URL) -> ConflictChoice {
        XCTFail("Unexpected conflict for \(url.lastPathComponent)")
        return .skip
    }

    func testCopyLeavesSourceAndCreatesTarget() throws {
        let source = try makeFile("a/note.txt", "hello")
        let destination = try makeFolder("b")

        let result = ops.transfer([source], to: destination, mode: .copy, resolve: failOnConflict)

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "hello")
        XCTAssertTrue(exists(source))
        XCTAssertEqual(result.completed.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testMoveRemovesSource() throws {
        let source = try makeFile("a/note.txt", "hello")
        let destination = try makeFolder("b")

        _ = ops.transfer([source], to: destination, mode: .move, resolve: failOnConflict)

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "hello")
        XCTAssertFalse(exists(source))
    }

    func testConflictKeepBothAddsCopySuffix() throws {
        let source = try makeFile("a/note.txt", "new")
        let destination = try makeFolder("b")
        try makeFile("b/note.txt", "old")

        _ = ops.transfer([source], to: destination, mode: .copy) { _ in .keepBoth }
        _ = ops.transfer([source], to: destination, mode: .copy) { _ in .keepBoth }

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "old")
        XCTAssertEqual(read(destination.appendingPathComponent("note copy.txt")), "new")
        XCTAssertEqual(read(destination.appendingPathComponent("note copy 2.txt")), "new")
    }

    func testConflictReplaceSendsOldItemToTrash() throws {
        let source = try makeFile("a/note.txt", "new")
        let destination = try makeFolder("b")
        try makeFile("b/note.txt", "old")

        let result = ops.transfer([source], to: destination, mode: .copy) { _ in .replace }

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "new")
        XCTAssertEqual(trasher.trashed.count, 1)
        XCTAssertEqual(read(trasher.trashed[0]), "old")
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testReplaceKeepsOldItemWhenTrashFails() throws {
        let source = try makeFile("a/note.txt", "new")
        let destination = try makeFolder("b")
        try makeFile("b/note.txt", "old")
        trasher.shouldFail = true

        let result = ops.transfer([source], to: destination, mode: .move) { _ in .replace }

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "old")
        XCTAssertTrue(exists(source))
        XCTAssertEqual(result.failures.count, 1)
    }

    func testConflictSkipChangesNothing() throws {
        let source = try makeFile("a/note.txt", "new")
        let destination = try makeFolder("b")
        try makeFile("b/note.txt", "old")

        let result = ops.transfer([source], to: destination, mode: .move) { _ in .skip }

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "old")
        XCTAssertTrue(exists(source))
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testCopyIntoSameFolderDuplicatesWithoutAsking() throws {
        let source = try makeFile("a/note.txt", "hello")

        _ = ops.transfer([source], to: source.deletingLastPathComponent(), mode: .copy, resolve: failOnConflict)

        XCTAssertEqual(read(root.appendingPathComponent("a/note copy.txt")), "hello")
        XCTAssertEqual(read(source), "hello")
    }

    func testMoveIntoSameFolderDoesNothing() throws {
        let source = try makeFile("a/note.txt", "hello")

        let result = ops.transfer([source], to: source.deletingLastPathComponent(), mode: .move, resolve: failOnConflict)

        XCTAssertEqual(read(source), "hello")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("a").path), ["note.txt"])
        XCTAssertEqual(result.skipped.count, 1)
    }

    func testFolderCannotBeCopiedOrMovedIntoItself() throws {
        let folder = try makeFolder("a")
        let inner = try makeFolder("a/inner")
        try makeFile("a/note.txt")

        let intoSelf = ops.transfer([folder], to: folder, mode: .copy, resolve: failOnConflict)
        let intoDescendant = ops.transfer([folder], to: inner, mode: .move, resolve: failOnConflict)

        XCTAssertEqual(intoSelf.failures.count, 1)
        XCTAssertEqual(intoDescendant.failures.count, 1)
        XCTAssertTrue(exists(folder.appendingPathComponent("note.txt")))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: inner.path), [])
    }

    func testMoveAcrossDrivesCopiesThenRemovesSource() throws {
        let crossDrive = FileOperations(trasher: trasher, sameDrive: { _, _ in false })
        let source = try makeFile("a/note.txt", "hello")
        let destination = try makeFolder("b")

        _ = crossDrive.transfer([source], to: destination, mode: .move, resolve: failOnConflict)

        XCTAssertEqual(read(destination.appendingPathComponent("note.txt")), "hello")
        XCTAssertFalse(exists(source))
    }

    func testMoveAcrossDrivesKeepsSourceWhenCopyFails() throws {
        let crossDrive = FileOperations(trasher: trasher, sameDrive: { _, _ in false })
        let source = try makeFile("a/note.txt", "hello")
        let missing = root.appendingPathComponent("does-not-exist")

        let result = crossDrive.transfer([source], to: missing, mode: .move, resolve: failOnConflict)

        XCTAssertEqual(read(source), "hello")
        XCTAssertEqual(result.failures.count, 1)
    }

    func testNewFolderPicksAFreeName() throws {
        let work = try makeFolder("work")

        let first = try ops.newFolder(in: work)
        let second = try ops.newFolder(in: work)

        XCTAssertEqual(first.lastPathComponent, "New Folder")
        XCTAssertEqual(second.lastPathComponent, "New Folder 2")
        XCTAssertTrue(exists(second))
    }

    func testRenameChangesTheName() throws {
        let source = try makeFile("a/old.txt", "hello")

        let renamed = try ops.rename(source, to: "new.txt")

        XCTAssertEqual(read(renamed), "hello")
        XCTAssertFalse(exists(source))
    }

    func testRenameRefusesTakenOrInvalidNames() throws {
        let source = try makeFile("a/old.txt", "hello")
        try makeFile("a/taken.txt", "other")

        XCTAssertThrowsError(try ops.rename(source, to: "taken.txt"))
        XCTAssertThrowsError(try ops.rename(source, to: ""))
        XCTAssertThrowsError(try ops.rename(source, to: "a/b"))
        XCTAssertEqual(read(root.appendingPathComponent("a/taken.txt")), "other")
        XCTAssertEqual(read(source), "hello")
    }

    func testTrashGoesThroughTheTrasher() throws {
        let source = try makeFile("a/note.txt", "hello")

        let failures = ops.trash([source])

        XCTAssertTrue(failures.isEmpty)
        XCTAssertFalse(exists(source))
        XCTAssertEqual(trasher.trashed.count, 1)
    }
}

final class DrivesTests: XCTestCase {
    func testStartupDriveIsListedWithCapacity() throws {
        let drives = Drives.mounted()
        let startup = try XCTUnwrap(drives.first { $0.url.path == "/" })

        XCTAssertGreaterThan(startup.totalBytes, 0)
        XCTAssertGreaterThan(startup.availableBytes, 0)
        XCTAssertLessThanOrEqual(startup.usedFraction, 1)
        XCTAssertFalse(startup.name.isEmpty)
    }
}
