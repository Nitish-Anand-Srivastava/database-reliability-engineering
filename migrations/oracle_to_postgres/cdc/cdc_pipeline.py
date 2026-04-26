def capture_changes():
    return []

def apply_changes(changes):
    for c in changes:
        print("apply", c)

if __name__ == '__main__':
    changes = capture_changes()
    apply_changes(changes)
