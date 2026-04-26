class ActionExecutor:
    def __init__(self):
        pass

    def execute(self, action):
        if action == "prepare_action":
            return self.run_pipeline()
        return "no_execution"

    def run_pipeline(self):
        print("Executing automated response pipeline")
        return "execution_triggered"

if __name__ == '__main__':
    executor = ActionExecutor()
    print(executor.execute("prepare_action"))
