class PrecheckPolicy:
    def __init__(self, threshold=100):
        self.threshold = threshold

    def evaluate(self, active_sessions):
        if active_sessions > self.threshold:
            return "reject"
        return "approve"

if __name__ == '__main__':
    policy = PrecheckPolicy()
    print(policy.evaluate(120))
