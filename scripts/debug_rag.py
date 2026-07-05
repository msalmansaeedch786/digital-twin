import json
import requests

url = "https://jukwx9moj4.execute-api.eu-central-1.amazonaws.com/chat"
payload = {
    "message": "What certifications do you have other than AWS?",
    "history": []
}
headers = {"Content-Type": "application/json"}
response = requests.post(url, json=payload)
print(response.json())
