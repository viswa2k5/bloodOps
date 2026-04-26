import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Donors')

def lambda_handler(event, context):
    method = event['httpMethod']
    if method == 'POST':
        return register_donor(event)
    elif method == 'GET':
        return get_donors(event)
    else:
        return response(405, {'message': 'Method not allowed'})

def register_donor(event):
    body = json.loads(event['body'])
    donor_id = str(uuid.uuid4())
    item = {
        'DonorID': donor_id,
        'Name': body['name'],
        'BloodType': body['blood_type'],
        'Location': body['location'],
        'Phone': body['phone'],
        'Availability': body.get('availability', 'available'),
        'LastDonationDate': body.get('last_donation_date', ''),
        'CreatedAt': datetime.now().isoformat()
    }
    table.put_item(Item=item)
    return response(201, {'message': 'Donor registered successfully', 'DonorID': donor_id})

def get_donors(event):
    params = event.get('queryStringParameters') or {}
    blood_type = params.get('blood_type')
    if blood_type:
        result = table.scan(
            FilterExpression='BloodType = :bt',
            ExpressionAttributeValues={':bt': blood_type}
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