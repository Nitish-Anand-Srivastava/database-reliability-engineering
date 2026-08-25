class Heartbeat:
    def __init__(self, threshold=3):
        self.threshold = threshold
        self.fail_count = 0

    def check(self, status: bool):
        if not status:
            self.fail_count += 1
        else:
            self.fail_count = 0

        return self.fail_count >= self.threshold

if __name__ == '__main__':
    hb = Heartbeat()
    print(hb.check(True))
