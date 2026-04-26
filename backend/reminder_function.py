import json
import boto3
from datetime import datetime, timedelta

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
table = dynamodb.Table('DonationHistory')
donors_table = dynamodb.Table('Donors')
SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:065837433541:reminder-alerts'

def lambda_handler(event, context):
    three_months_ago = (datetime.now() - timedelta(days=90)).isoformat()
    history_result = table.scan()
    recent_donors = {}
    for item in history_result['Items']:
        donor_id = item['DonorID']
        donation_date = item['DonationDate']
        if donor_id not in recent_donors or donation_date > recent_donors[donor_id]:
            recent_donors[donor_id] = donation_date
    eligible_donors = [
        donor_id for donor_id, last_date in recent_donors.items()
        if last_date < three_months_ago
    ]
    donors_result = donors_table.scan()
    reminders_sent = 0
    for donor in donors_result['Items']:
        if donor['DonorID'] in eligible_donors:
            try:
                sns.publish(
                    TopicArn=SNS_TOPIC_ARN,
                    Message=f"Dear {donor['Name']}, you are eligible to donate blood again. Please consider donating today!",
                    Subject='BloodOps - Time to Donate Again!'
                )
                reminders_sent += 1
            except Exception:
                pass
    return response(200, {
        'message': f'Reminders sent to {reminders_sent} donors',
        'eligible_count': len(eligible_donors)
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