import json
import boto3
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

donors_table = dynamodb.Table('Donors')
requests_table = dynamodb.Table('Requests')

BLOOD_COMPATIBILITY = {
    'A+': ['A+', 'A-', 'O+', 'O-'],
    'A-': ['A-', 'O-'],
    'B+': ['B+', 'B-', 'O+', 'O-'],
    'B-': ['B-', 'O-'],
    'AB+': ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'],
    'AB-': ['A-', 'B-', 'AB-', 'O-'],
    'O+': ['O+', 'O-'],
    'O-': ['O-']
}

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

def lambda_handler(event, context):
    try:
        params = event.get('queryStringParameters') or {}
        request_id = params.get('request_id')
        if not request_id:
            return response(400, {'message': 'request_id is required'})

        request_result = requests_table.get_item(Key={'RequestID': request_id})
        if 'Item' not in request_result:
            return response(404, {'message': 'Request not found'})

        blood_request = request_result['Item']
        needed_type = blood_request['BloodType']
        compatible_types = BLOOD_COMPATIBILITY.get(needed_type, [])

        donors_result = donors_table.scan()
        matching_donors = [
            d for d in donors_result['Items']
            if d['BloodType'] in compatible_types
            and d.get('Availability') == 'Available'
        ]

        # Send urgent alert emails to matching donors
        if matching_donors and blood_request.get('Urgency') == 'Urgent':
            for donor in matching_donors:
                donor_email = donor.get('Email', '')
                donor_name = donor.get('Name', 'Donor')
                if donor_email:
                    try:
                        sns.publish(
                            TopicArn='arn:aws:sns:us-east-1:065837433541:urgent-blood-alerts',
                            Message=f"""Dear {donor_name},

URGENT BLOOD REQUEST!

Hospital: {blood_request.get('HospitalName', 'Unknown')}
Blood Type Needed: {needed_type}
Quantity: {blood_request.get('Quantity', 'Unknown')} units
Urgency: URGENT

Your blood type ({donor.get('BloodType')}) is compatible. Please contact the hospital immediately!

Thank you for saving a life!

- BloodOps Team""",
                            Subject=f'URGENT - Blood Needed at {blood_request.get("HospitalName", "Hospital")}!'
                        )
                    except Exception as e:
                        print(f"Failed to send urgent alert to {donor_name}: {str(e)}")

        return response(200, {
            'request': blood_request,
            'matching_donors': matching_donors,
            'total_matches': len(matching_donors)
        })
    except Exception as e:
        return response(500, {'message': str(e)})

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body, cls=DecimalEncoder)
    }