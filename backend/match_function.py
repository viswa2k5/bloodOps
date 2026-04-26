import json
import boto3

dynamodb = boto3.resource('dynamodb')
donors_table = dynamodb.Table('Donors')
requests_table = dynamodb.Table('Requests')
sns = boto3.client('sns')

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

def lambda_handler(event, context):
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
        and d.get('Availability') == 'available'
    ]
    if matching_donors and blood_request.get('Urgency') == 'Urgent':
        try:
            sns.publish(
                TopicArn='arn:aws:sns:us-east-1:065837433541:urgent-blood-alerts',
                Message=f"Urgent blood request for {needed_type}. Hospital: {blood_request['HospitalName']}",
                Subject='Urgent Blood Request'
            )
        except Exception:
            pass
    return response(200, {
        'request': blood_request,
        'matching_donors': matching_donors,
        'total_matches': len(matching_donors)
    })

def response(status_code, body):
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(body)
    }