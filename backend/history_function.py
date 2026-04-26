import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('DonationHistory')

def lambda_handler(event, context):
    method = event['httpMethod']
    if method == 'POST':
        return add_history(event)
    elif method == 'GET':
        return get_history(event)
    else:
        return response(405, {'message': 'Method not allowed'})

def add_history(event):
    body = json.loads(event['body'])
    history_id = str(uuid.uuid4())
    item = {
        'HistoryID': history_id,
        'DonorID': body['donor_id'],
        'DonationDate': body.get('donation_date', datetime.now().isoformat()),
        'HospitalName': body['hospital_name'],
        'CertificateURL': body.get('certificate_url', '')
    }
    table.put_item(Item=item)
    return response(201, {'message': 'History added successfully', 'HistoryID': history_id})

def get_history(event):
    params = event.get('queryStringParameters') or {}
    donor_id = params.get('donor_id')
    if donor_id:
        result = table.scan(
            FilterExpression='DonorID = :d',
            ExpressionAttributeValues={':d': donor_id}
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