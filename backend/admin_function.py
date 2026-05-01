import json
import boto3
from collections import Counter
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
donors_table = dynamodb.Table('Donors')
requests_table = dynamodb.Table('Requests')
history_table = dynamodb.Table('DonationHistory')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

def lambda_handler(event, context):
    try:
        donors = donors_table.scan()['Items']
        requests = requests_table.scan()['Items']
        history = history_table.scan()['Items']
        blood_type_counts = Counter(d['BloodType'] for d in donors if d.get('Availability') == 'Available')
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
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(dashboard, cls=DecimalEncoder)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'message': str(e)})
        }