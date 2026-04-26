import json
import boto3
import uuid
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
import io

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
history_table = dynamodb.Table('DonationHistory')
BUCKET_NAME = 'bloodops-certificates-bucket'

def lambda_handler(event, context):
    params = event.get('queryStringParameters') or {}
    donor_id = params.get('donor_id')
    donor_name = params.get('donor_name', 'Donor')
    blood_type = params.get('blood_type', '')
    if not donor_id:
        return response(400, {'message': 'donor_id is required'})
    pdf_buffer = io.BytesIO()
    c = canvas.Canvas(pdf_buffer, pagesize=letter)
    c.setFont('Helvetica-Bold', 24)
    c.drawCentredString(300, 700, 'BloodOps Donation Certificate')
    c.setFont('Helvetica', 16)
    c.drawCentredString(300, 650, f'This certifies that {donor_name}')
    c.drawCentredString(300, 620, f'Blood Type: {blood_type}')
    c.drawCentredString(300, 590, f'has successfully donated blood')
    c.drawCentredString(300, 560, f'Date: {datetime.now().strftime("%B %d, %Y")}')
    c.drawCentredString(300, 500, 'Thank you for saving lives!')
    c.save()
    pdf_buffer.seek(0)
    certificate_key = f'certificates/{donor_id}/{uuid.uuid4()}.pdf'
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=certificate_key,
        Body=pdf_buffer.getvalue(),
        ContentType='application/pdf'
    )
    certificate_url = f'https://{BUCKET_NAME}.s3.amazonaws.com/{certificate_key}'
    return response(200, {
        'message': 'Certificate generated successfully',
        'certificate_url': certificate_url
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