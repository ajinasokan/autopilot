import requests

root = "http://localhost:8080"


def get(path):
    return requests.get(root + path).json()


def test_greet():
    greet = get("/texts?key=txtGreet")[0]
    assert greet["text"] == "Hello World!"
