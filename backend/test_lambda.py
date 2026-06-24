def handler(event, context):
    try:
        import main
        return {"statusCode": 200, "body": "main imported successfully!"}
    except Exception as e:
        import traceback
        return {"statusCode": 500, "body": traceback.format_exc()}
