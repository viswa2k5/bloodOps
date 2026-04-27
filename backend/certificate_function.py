import json
import boto3
import os
from datetime import datetime
from decimal import Decimal

# ============================================================
# CERTIFICATE FUNCTION
# Generates a premium PDF donation certificate using ReportLab
# ============================================================

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

BUCKET_NAME = os.environ.get('BUCKET_NAME', 'bloodops-certificates-bucket')
REGION = os.environ.get('REGION', 'us-east-1')

donors_table = dynamodb.Table('Donors')
history_table = dynamodb.Table('DonationHistory')


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


def generate_certificate_pdf(donor_name, blood_type, donation_date, hospital_name, donor_id):
    from reportlab.lib.pagesizes import A4
    from reportlab.lib import colors
    from reportlab.lib.units import cm
    from reportlab.pdfgen import canvas
    import io

    buffer = io.BytesIO()
    width, height = A4  # 595 x 842 pts

    c = canvas.Canvas(buffer, pagesize=A4)

    # ── BACKGROUND ──
    c.setFillColor(colors.HexColor('#fffaf9'))
    c.rect(0, 0, width, height, fill=1, stroke=0)

    # ── OUTER BORDER (thick dark red) ──
    c.setStrokeColor(colors.HexColor('#8B0000'))
    c.setLineWidth(6)
    c.rect(18, 18, width - 36, height - 36, fill=0, stroke=1)

    # ── INNER BORDER (thin) ──
    c.setStrokeColor(colors.HexColor('#cc3333'))
    c.setLineWidth(1.5)
    c.rect(28, 28, width - 56, height - 56, fill=0, stroke=1)

    # ── CORNER DIAMOND ORNAMENTS ──
    def diamond(cx, cy, size=7):
        c.setFillColor(colors.HexColor('#8B0000'))
        p = c.beginPath()
        p.moveTo(cx, cy + size)
        p.lineTo(cx + size, cy)
        p.lineTo(cx, cy - size)
        p.lineTo(cx - size, cy)
        p.close()
        c.drawPath(p, fill=1, stroke=0)

    diamond(22, 22)
    diamond(width - 22, 22)
    diamond(22, height - 22)
    diamond(width - 22, height - 22)

    # ── TOP HEADER BAND ──
    c.setFillColor(colors.HexColor('#8B0000'))
    c.rect(28, height - 112, width - 56, 72, fill=1, stroke=0)

    # Dot decorations in band
    c.setFillColor(colors.HexColor('#ffffff'))
    for x in [55, 72, 89, width - 55, width - 72, width - 89]:
        c.circle(x, height - 76, 3, fill=1, stroke=0)

    # BloodOps name
    c.setFillColor(colors.white)
    c.setFont('Helvetica-Bold', 13)
    c.drawCentredString(width / 2, height - 60, 'B L O O D O P S')
    c.setFont('Helvetica', 8)
    c.setFillColor(colors.HexColor('#ffcccc'))
    c.drawCentredString(width / 2, height - 75, 'Serverless Blood Bank Management System')

    # ── CERTIFICATE TITLE ──
    c.setFillColor(colors.HexColor('#8B0000'))
    c.setFont('Helvetica-Bold', 24)
    c.drawCentredString(width / 2, height - 150, 'CERTIFICATE OF APPRECIATION')

    c.setFillColor(colors.HexColor('#cc3333'))
    c.setFont('Helvetica', 10)
    c.drawCentredString(width / 2, height - 168, 'IN RECOGNITION OF A NOBLE ACT OF BLOOD DONATION')

    # ── ORNAMENTAL DIVIDER ──
    c.setStrokeColor(colors.HexColor('#cc3333'))
    c.setLineWidth(1)
    c.line(80, height - 182, width - 80, height - 182)
    c.setFillColor(colors.HexColor('#8B0000'))
    c.circle(width / 2, height - 182, 4, fill=1, stroke=0)
    c.circle(width / 2 - 28, height - 182, 2, fill=1, stroke=0)
    c.circle(width / 2 + 28, height - 182, 2, fill=1, stroke=0)

    # ── PRESENTED TO ──
    c.setFillColor(colors.HexColor('#555555'))
    c.setFont('Helvetica', 11)
    c.drawCentredString(width / 2, height - 210, 'This certificate is proudly presented to')

    # ── DONOR NAME ──
    c.setFillColor(colors.HexColor('#8B0000'))
    c.setFont('Helvetica-Bold', 28)
    c.drawCentredString(width / 2, height - 248, donor_name.upper())

    # Name underline
    nw = c.stringWidth(donor_name.upper(), 'Helvetica-Bold', 28)
    c.setStrokeColor(colors.HexColor('#cc3333'))
    c.setLineWidth(1.5)
    c.line(width / 2 - nw / 2, height - 256, width / 2 + nw / 2, height - 256)

    # ── CITATION ──
    c.setFillColor(colors.HexColor('#333333'))
    c.setFont('Helvetica', 10)
    c.drawCentredString(width / 2, height - 276,
                        'for their selfless act of donating blood and contributing to saving precious human lives.')

    # ── DETAILS BOX ──
    bx, by, bw, bh = 60, height - 400, width - 120, 100
    c.setFillColor(colors.HexColor('#fff0f0'))
    c.setStrokeColor(colors.HexColor('#ffaaaa'))
    c.setLineWidth(1)
    c.roundRect(bx, by, bw, bh, 8, fill=1, stroke=1)

    details = [
        ('BLOOD TYPE', blood_type),
        ('DONATION DATE', donation_date),
        ('HOSPITAL / CENTRE', hospital_name[:40]),
        ('DONOR ID', donor_id),
    ]
    col1 = bx + 20
    col2 = bx + 160
    row_start = by + bh - 20
    for i, (label, value) in enumerate(details):
        ry = row_start - i * 22
        c.setFillColor(colors.HexColor('#cc3333'))
        c.circle(col2 - 12, ry + 3, 2, fill=1, stroke=0)
        c.setFillColor(colors.HexColor('#888888'))
        c.setFont('Helvetica', 8)
        c.drawString(col1, ry, label)
        c.setFillColor(colors.HexColor('#1a0005'))
        c.setFont('Helvetica-Bold', 10)
        c.drawString(col2, ry, str(value))

    # ── HEROIC QUOTE BOX ──
    qy = height - 452
    c.setFillColor(colors.HexColor('#8B0000'))
    c.roundRect(60, qy, width - 120, 40, 6, fill=1, stroke=0)
    c.setFillColor(colors.white)
    c.setFont('Helvetica-BoldOblique', 10)
    c.drawCentredString(width / 2, qy + 26,
                        '"The blood you donate gives someone another chance at life.')
    c.drawCentredString(width / 2, qy + 12,
                        'One day, that someone may be a person you love."')

    # ── IMPACT LINE ──
    c.setFillColor(colors.HexColor('#555555'))
    c.setFont('Helvetica', 10)
    c.drawCentredString(width / 2, height - 472,
                        'Your single donation has the potential to save up to 3 lives.')

    # ── SIGNATURE SECTION ──
    sy = height - 570

    # Left signature line
    c.setStrokeColor(colors.HexColor('#aaaaaa'))
    c.setLineWidth(1)
    c.line(75, sy, 215, sy)
    c.setFillColor(colors.HexColor('#333333'))
    c.setFont('Helvetica-Bold', 9)
    c.drawCentredString(145, sy - 13, 'Authorised Signatory')
    c.setFillColor(colors.HexColor('#888888'))
    c.setFont('Helvetica', 8)
    c.drawCentredString(145, sy - 24, 'BloodOps Administration')

    # Right signature line
    c.line(width - 215, sy, width - 75, sy)
    c.setFillColor(colors.HexColor('#333333'))
    c.setFont('Helvetica-Bold', 9)
    c.drawCentredString(width - 145, sy - 13, 'Medical Officer')
    c.setFillColor(colors.HexColor('#888888'))
    c.setFont('Helvetica', 8)
    c.drawCentredString(width - 145, sy - 24, hospital_name[:25])

    # ── OFFICIAL SEAL (center) ──
    sx, sy2 = width / 2, sy - 8
    c.setStrokeColor(colors.HexColor('#8B0000'))
    c.setFillColor(colors.HexColor('#fff0f0'))
    c.setLineWidth(2)
    c.circle(sx, sy2, 34, fill=1, stroke=1)
    c.setStrokeColor(colors.HexColor('#cc3333'))
    c.setLineWidth(1)
    c.circle(sx, sy2, 28, fill=0, stroke=1)
    c.setFillColor(colors.HexColor('#8B0000'))
    c.setFont('Helvetica-Bold', 7)
    c.drawCentredString(sx, sy2 + 10, 'BLOODOPS')
    c.setFont('Helvetica', 6)
    c.drawCentredString(sx, sy2 + 2, 'OFFICIAL SEAL')
    c.setFont('Helvetica-Bold', 16)
    c.drawCentredString(sx, sy2 - 12, blood_type)

    # ── BOTTOM BAND ──
    c.setFillColor(colors.HexColor('#8B0000'))
    c.rect(28, 28, width - 56, 44, fill=1, stroke=0)

    issue_date = datetime.now().strftime('%B %d, %Y at %I:%M %p UTC')
    c.setFillColor(colors.HexColor('#ffcccc'))
    c.setFont('Helvetica', 7)
    c.drawCentredString(width / 2, 54,
                        f'Certificate ID: BLOODOPS-{donor_id[:8].upper()}  |  Issued: {issue_date}')
    c.setFillColor(colors.white)
    c.setFont('Helvetica-Bold', 8)
    c.drawCentredString(width / 2, 40,
                        'Every drop counts. Every second matters.  —  BloodOps')

    c.save()
    buffer.seek(0)
    return buffer


def lambda_handler(event, context):
    try:
        params = event.get('queryStringParameters') or {}
        donor_id = params.get('donor_id')
        history_id = params.get('history_id')

        if not donor_id:
            return response(400, {'message': 'donor_id is required'})

        # Get donor details
        donor_result = donors_table.get_item(Key={'DonorID': donor_id})
        if 'Item' not in donor_result:
            return response(404, {'message': 'Donor not found'})

        donor = donor_result['Item']
        donor_name = donor.get('Name', 'Unknown Donor')
        blood_type = donor.get('BloodType', 'Unknown')

        # Get history details if history_id provided
        hospital_name = 'BloodOps Donation Centre'
        donation_date = datetime.now().strftime('%B %d, %Y')

        if history_id:
            history_result = history_table.get_item(Key={'HistoryID': history_id})
            if 'Item' in history_result:
                history = history_result['Item']
                hospital_name = history.get('HospitalName', hospital_name)
                raw_date = history.get('DonationDate', '')
                if raw_date:
                    try:
                        dt = datetime.fromisoformat(raw_date[:10])
                        donation_date = dt.strftime('%B %d, %Y')
                    except Exception:
                        donation_date = raw_date[:10]

        # Generate PDF
        pdf_buffer = generate_certificate_pdf(
            donor_name=donor_name,
            blood_type=blood_type,
            donation_date=donation_date,
            hospital_name=hospital_name,
            donor_id=donor_id
        )

        # Upload to S3
        file_key = f'certificates/{donor_id}/{datetime.now().strftime("%Y%m%d%H%M%S")}_certificate.pdf'
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=file_key,
            Body=pdf_buffer.getvalue(),
            ContentType='application/pdf'
        )

        # Generate pre-signed URL valid for 1 hour
        download_url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': BUCKET_NAME, 'Key': file_key},
            ExpiresIn=3600
        )

        # Update history record with certificate URL
        if history_id:
            try:
                history_table.update_item(
                    Key={'HistoryID': history_id},
                    UpdateExpression='SET CertificateURL = :url',
                    ExpressionAttributeValues={':url': download_url}
                )
            except Exception:
                pass

        return response(200, {
            'message': 'Certificate generated successfully',
            'certificate_url': download_url,
            'donor_name': donor_name,
            'blood_type': blood_type,
            'donation_date': donation_date,
            'hospital_name': hospital_name
        })

    except Exception as e:
        return response(500, {'message': str(e)})