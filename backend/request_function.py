import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Requests')

def lambda_handler(event, context):
    method = event['httpMethod']
    if method == 'POST':
        return create_request(event)
    elif method == 'GET':
        return get_requests(event)
    else:
        return response(405, {'message': 'Method not allowed'})

def create_request(event):
    body = json.loads(event['body'])
    request_id = str(uuid.uuid4())
    item = {
        'RequestID': request_id,
        'HospitalName': body['hospital_name'],
        'BloodType': body['blood_type'],
        'Quantity': body['quantity'],
        'Urgency': body['urgency'],
        'Status': 'pending',
        'Timestamp': datetime.now().isoformat()
    }
    table.put_item(Item=item)
    return response(201, {'message': 'Request created successfully', 'RequestID': request_id})

def get_requests(event):
    params = event.get('queryStringParameters') or {}
    status = params.get('status')
    if status:
        result = table.scan(
            FilterExpression='#s = :s',
            ExpressionAttributeNames={'#s': 'Status'},
            ExpressionAttributeValues={':s': status}
        )
    else:
        result = table.scan()
    return response(200, result['Items'])

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }
