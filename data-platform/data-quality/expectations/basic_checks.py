def check_values_present(data, key):
    return all(key in row for row in data)
