struct AsyncGate: Sendable {
    private let arrival = Signal()
    private let release = Signal()

    func wait() async {
        await arrival.send()
        await release.wait()
    }

    func waitUntilWaiting() async {
        await arrival.wait()
    }

    func open() async {
        await release.send()
    }

    private actor Signal {
        private var waiters: [AsyncStream<Void>.Continuation]? = []

        func wait() async {
            guard waiters != nil else { return }
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            waiters?.append(continuation)
            for await _ in stream {}
        }

        func send() {
            let pending = waiters
            waiters = nil
            pending?.forEach { $0.finish() }
        }
    }
}
