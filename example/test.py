import requests
import time

root = "http://localhost:8080"


def get(path):
    return requests.get(root + path).json()


def test_increment():
    get("/tap?text=Reset")
    time.sleep(0.1)

    txtCount = get("/texts?key=txtCount")[0]
    assert txtCount["text"] == "0"

    get("/tap?text=")  # "+" icon text
    time.sleep(0.1)

    txtCount = get("/texts?key=txtCount")[0]
    assert txtCount["text"] == "1"
