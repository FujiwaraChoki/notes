import Foundation

class Debouncer {
    private let delay: TimeInterval
    private var timer: Timer?

    init(delay: TimeInterval = 0.5) {
        self.delay = delay
    }

    func call(action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
