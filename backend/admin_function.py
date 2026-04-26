import json
import boto3
from collections import Counter

dynamodb = boto3.resource('dynamodb')
donors_table = dynamodb.Table('Donors')
requests_table = dynamodb.Table('Requests')
history_table = dynamodb.Table('DonationHistory')

def lambda_handler(event, context):
    donors = donors_table.scan()['Items']
    requests = requests_table.scan()['Items']
    history = history_table.scan()['Items']
    blood_type_counts = Counter(d['BloodType'] for d in donors)
    pending_requests = [r for r in requests if r.get('Status') == 'pending']
    matched_requests = [r for r in requests if r.get('Status') == 'matched']
    dashboard = {
        'total_donors': len(donors),
        'total_requests': len(requests),
        'total_donations': len(history),
        'blood_type_availability': dict(blood_type_counts),
        'pending_requests': pending_requests,
        'matched_requests': matched_requests
    }
    return response(200, dashboard)

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }