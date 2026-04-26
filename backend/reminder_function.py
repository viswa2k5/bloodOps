import json
import boto3
from datetime import datetime, timedelta
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

table = dynamodb.Table('DonationHistory')
donors_table = dynamodb.Table('Donors')

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)

def lambda_handler(event, context):
    try:
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
                donor_email = donor.get('Email', '')
                donor_name = donor.get('Name', 'Donor')

                if donor_email:
                    try:
                        # Create a personal SNS topic for this donor's email
                        sns_client = boto3.client('sns')
                        
                        # Publish to reminder topic with donor details
                        sns_client.publish(
                            TopicArn='arn:aws:sns:us-east-1:065837433541:reminder-alerts',
                            Message=f"""Dear {donor_name},

You are now eligible to donate blood again! It has been over 3 months since your last donation.

Your donation can save up to 3 lives. Please consider visiting your nearest blood bank today.

Thank you for being a hero!

- BloodOps Team""",
                            Subject=f'BloodOps - Time to Donate Again, {donor_name}!',
                            MessageAttributes={
                                'email': {
                                    'DataType': 'String',
                                    'StringValue': donor_email
                                }
                            }
                        )
                        reminders_sent += 1
                    except Exception as e:
                        print(f"Failed to send reminder to {donor_name}: {str(e)}")

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': f'Reminders sent to {reminders_sent} donors',
                'eligible_count': len(eligible_donors)
            })
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