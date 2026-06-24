import boto3
import json

session = boto3.Session(profile_name='digital-twin')
client = session.client('bedrock-runtime', region_name='eu-central-1')

try:
    response = client.invoke_model(
        modelId='amazon.titan-embed-text-v2:0',
        body=json.dumps({"inputText": "Hello world"}),
        accept='application/json',
        contentType='application/json'
    )
    print("Success:", response['body'].read().decode('utf-8'))
except Exception as e:
    print("Error:", str(e))
