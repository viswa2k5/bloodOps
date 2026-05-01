import json
import boto3
import uuid
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

history_table = dynamodb.Table('DonationHistory')
donors_table = dynamodb.Table('Donors')
requests_table = dynamodb.Table('Requests')


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body, cls=DecimalEncoder)
    }


def lambda_handler(event, context):
    try:
        method = event['httpMethod']
        if method == 'POST':
            return add_history(event)
        elif method == 'GET':
            return get_history(event)
        else:
            return response(405, {'message': 'Method not allowed'})
    except Exception as e:
        return response(500, {'message': str(e)})


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
    history_table.put_item(Item=item)

    # Auto-update donor availability to Unavailable
    try:
        donors_table.update_item(
            Key={'DonorID': body['donor_id']},
            UpdateExpression='SET Availability = :a, LastDonationDate = :d',
            ExpressionAttributeValues={
                ':a': 'Unavailable',
                ':d': body.get('donation_date', datetime.now().isoformat())[:10]
            }
        )
    except Exception:
        pass

    # Auto-update request status to completed
    try:
        request_id = body.get('request_id', '')
        if request_id:
            # If request_id provided update directly
            requests_table.update_item(
                Key={'RequestID': request_id},
                UpdateExpression='SET #s = :s',
                ExpressionAttributeNames={'#s': 'Status'},
                ExpressionAttributeValues={':s': 'completed'}
            )
        else:
            # Auto-find most recent pending request by hospital name
            result = requests_table.scan(
                FilterExpression='#s = :s AND HospitalName = :h',
                ExpressionAttributeNames={'#s': 'Status'},
                ExpressionAttributeValues={
                    ':s': 'pending',
                    ':h': body['hospital_name']
                }
            )
            if result['Items']:
                latest = sorted(
                    result['Items'],
                    key=lambda x: x.get('Timestamp', ''),
                    reverse=True
                )[0]
                requests_table.update_item(
                    Key={'RequestID': latest['RequestID']},
                    UpdateExpression='SET #s = :s',
                    ExpressionAttributeNames={'#s': 'Status'},
                    ExpressionAttributeValues={':s': 'completed'}
                )
    except Exception:
        pass

    return response(201, {
        'message': 'History added successfully',
        'HistoryID': history_id
    })


def get_history(event):
    params = event.get('queryStringParameters') or {}
    donor_id = params.get('donor_id')
    if donor_id:
        result = history_table.scan(
            FilterExpression='DonorID = :d',
            ExpressionAttributeValues={':d': donor_id}
        )
    else:
        result = history_table.scan()
    return response(200, result['Items'])