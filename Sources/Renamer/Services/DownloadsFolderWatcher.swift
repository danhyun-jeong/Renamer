import Foundation

class DownloadsFolderWatcher {
    var onNewFile: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private let downloadsURL: URL
    private var knownFileNames: Set<String> = []   // 폴더 내 파일명 추적 (신규 감지용)
    private var processedInodes: Set<ino_t> = []   // 처리 완료된 파일 inode 추적
    private var pendingItems: [String: DispatchWorkItem] = [:]
    private let watchQueue = DispatchQueue(label: "com.danhyun.renamer.watcher")

    init() {
        downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }

    func start() {
        if let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: nil
        ) {
            knownFileNames = Set(files.map { $0.lastPathComponent })
        }

        let fd = open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[Renamer] ⚠️ 다운로드 폴더 감시 실패")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: watchQueue
        )

        source?.setEventHandler { [weak self] in
            self?.detectNewFiles()
        }

        source?.setCancelHandler {
            close(fd)
        }

        source?.resume()
    }

    private func detectNewFiles() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: nil
        ) else { return }

        let currentNames = Set(files.map { $0.lastPathComponent })
        let newFileNames = currentNames.subtracting(knownFileNames)
        knownFileNames = currentNames

        for fileName in newFileNames {
            let ext = (fileName as NSString).pathExtension.lowercased()
            guard !["download", "crdownload", "part", "tmp", "swp"].contains(ext) else { continue }
            guard !fileName.hasPrefix(".") else { continue }

            let fileURL = downloadsURL.appendingPathComponent(fileName)

            // inode 기반으로 이미 처리한 파일이면 건너뜀
            // (앱이 이름을 바꾼 파일이든, 사용자가 이름을 바꾼 파일이든 모두 해당)
            if let ino = inode(of: fileURL), processedInodes.contains(ino) { continue }

            let item = DispatchWorkItem { [weak self] in
                self?.watchQueue.async { [weak self] in
                    self?.pendingItems.removeValue(forKey: fileName)
                }
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

                // 타이머 발동 직전 inode 재확인
                if let ino = self?.inode(of: fileURL), self?.processedInodes.contains(ino) == true { return }

                self?.onNewFile?(fileURL)
            }

            pendingItems[fileName] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
        }
    }

    /// 파일을 처리하기 직전(rename 전) 호출. inode를 호출 시점에 즉시 읽어 값만 watchQueue에 전달.
    /// rename 후에는 원본 경로가 사라지므로 반드시 rename 전에 호출해야 함.
    func markProcessed(url: URL) {
        // inode를 현재 스레드에서 동기적으로 읽음 (파일이 아직 원본 경로에 존재할 때)
        guard let ino = inode(of: url) else { return }
        watchQueue.async { [weak self] in
            self?.processedInodes.insert(ino)
        }
    }

    func stop() {
        source?.cancel()
        source = nil
        watchQueue.async { [weak self] in
            self?.pendingItems.values.forEach { $0.cancel() }
            self?.pendingItems.removeAll()
        }
    }

    private func inode(of url: URL) -> ino_t? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return st.st_ino
    }
}
