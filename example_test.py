import requests

root = "http://localhost:8080"


def get(path):
    return requests.get(root + path).json()


def test_greet():
    greet = get("/texts?key=txtGreet")[0]
    assert greet["text"] == "Hello World!"

def test_scroll():
    res = get("/scroll-into?scrollable-key=number_list&key=list_item_30&dy=-200&dx=0")
    assert res["status"] == "success"

    res = get("/tap?key=list_item_30")
    assert res["status"] == "success"
    