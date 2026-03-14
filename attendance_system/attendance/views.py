from django.utils import timezone
import pytz
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import load_der_public_key
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.exceptions import InvalidSignature
import base64
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
from datetime import timedelta, datetime
import uuid
import qrcode
import base64
from io import BytesIO

from .models import Class, Session, AttendanceRecord, Enrollment
from users.models import Teacher, Student, Device


def format_timestamp(timestamp):
    karachi_tz = pytz.timezone('Asia/Karachi')
    local_time = timestamp.astimezone(karachi_tz)
    return local_time.strftime('%d %b %Y, %I:%M %p')

def generate_qr_image(data):
    qr = qrcode.make(data)
    buffer = BytesIO()
    qr.save(buffer, format='PNG')
    return base64.b64encode(buffer.getvalue()).decode()


class GenerateQRView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        # Only teachers allowed
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can generate QR codes'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            teacher = Teacher.objects.get(user=request.user)
        except Teacher.DoesNotExist:
            return Response(
                {'error': 'Teacher record not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        class_id = request.data.get('class_id')
        if not class_id:
            return Response(
                {'error': 'class_id is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Make sure class belongs to this teacher
        try:
            class_obj = Class.objects.get(id=class_id, teacher=teacher)
        except Class.DoesNotExist:
            return Response(
                {'error': 'Class not found or not yours'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Close any existing active session
        Session.objects.filter(
            class_ref=class_obj,
            is_active=True
        ).update(is_active=False)

        # Generate token — 15 seconds expiry
        qr_token = str(uuid.uuid4())
        expires_at = timezone.now() + timedelta(seconds=15)

        # Create session
        session = Session.objects.create(
            class_ref=class_obj,
            teacher=teacher,
            qr_token=qr_token,
            expires_at=expires_at,
            is_active=True
        )

        # Generate QR image
        qr_data = f"{session.id}:{qr_token}"
        qr_image = generate_qr_image(qr_data)

        return Response({
            'session_id': session.id,
            'qr_token': qr_token,
            'qr_image': f"data:image/png;base64,{qr_image}",
            'expires_at': expires_at,
            'class_name': class_obj.name,
            'subject': class_obj.subject,
        }, status=status.HTTP_201_CREATED)


class RefreshQRView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        # Only teachers allowed
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can refresh QR'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            teacher = Teacher.objects.get(user=request.user)
            session = Session.objects.get(
                id=session_id,
                teacher=teacher,
                is_active=True,
                is_submitted=False
            )
        except Teacher.DoesNotExist:
            return Response({'error': 'Teacher not found'}, status=status.HTTP_404_NOT_FOUND)
        except Session.DoesNotExist:
            return Response({'error': 'Active session not found'}, status=status.HTTP_404_NOT_FOUND)

        # Generate new token — reset 15 second timer
        new_token = str(uuid.uuid4())
        session.previous_qr_token = session.qr_token  # save old token
        session.qr_token = new_token
        session.expires_at = timezone.now() + timedelta(seconds=15)
        session.save()

        # Generate new QR image
        qr_data = f"{session.id}:{new_token}"
        qr_image = generate_qr_image(qr_data)

        return Response({
            'session_id': session.id,
            'qr_token': new_token,
            'qr_image': f"data:image/png;base64,{qr_image}",
            'expires_at': session.expires_at,
        })


class StopSessionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can stop sessions'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            teacher = Teacher.objects.get(user=request.user)
            session = Session.objects.get(
                id=session_id,
                teacher=teacher,
                is_active=True
            )
        except (Teacher.DoesNotExist, Session.DoesNotExist):
            return Response(
                {'error': 'Active session not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Stop the session
        session.is_active = False
        session.stopped_at = timezone.now()
        session.save()

        # Auto mark all enrolled students as absent if they didn't scan
        enrolled_students = Enrollment.objects.filter(
            class_enrolled=session.class_ref
        ).values_list('student', flat=True)

        already_present = AttendanceRecord.objects.filter(
            session=session
        ).values_list('student', flat=True)

        # Mark absent for students who didn't scan
        absent_students = set(enrolled_students) - set(already_present)
        for student_id in absent_students:
            student = Student.objects.get(id=student_id)
            AttendanceRecord.objects.create(
                session=session,
                student=student,
                device=None,
                status='absent',
                signature=''
            )

        return Response({
            'message': 'Session stopped successfully',
            'session_id': session.id,
            'stopped_at': session.stopped_at,
        })


class SessionAttendanceView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, session_id):
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can view attendance'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            session = Session.objects.get(id=session_id)
        except Session.DoesNotExist:
            return Response(
                {'error': 'Session not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Get all attendance records for this session
        records = AttendanceRecord.objects.filter(
            session=session
        ).select_related('student__user')

        students_data = []
        for record in records:
            students_data.append({
                'record_id': record.id,
                'roll_number': record.student.roll_number,
                'name': record.student.user.get_full_name(),
                'status': record.status,
                'timestamp': format_timestamp(record.timestamp),
            })

        # Sort — present first, then absent
        students_data.sort(key=lambda x: x['status'])

        return Response({
            'session_id': session.id,
            'class_name': session.class_ref.name,
            'subject': session.class_ref.subject,
            'is_active': session.is_active,
            'is_submitted': session.is_submitted,
            'total_enrolled': len(students_data),
            'total_present': sum(1 for s in students_data if s['status'] == 'present'),
            'total_absent': sum(1 for s in students_data if s['status'] == 'absent'),
            'students': students_data,
        })


class EditAttendanceView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, record_id):
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can edit attendance'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            record = AttendanceRecord.objects.get(id=record_id)
        except AttendanceRecord.DoesNotExist:
            return Response(
                {'error': 'Record not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Cannot edit submitted attendance
        if record.session.is_submitted:
            return Response(
                {'error': 'Cannot edit submitted attendance'},
                status=status.HTTP_400_BAD_REQUEST
            )

        new_status = request.data.get('status')
        if new_status not in ['present', 'absent']:
            return Response(
                {'error': 'Status must be present or absent'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Save as manual override
        record.status = new_status
        record.save()

        return Response({
            'message': 'Attendance updated',
            'record_id': record.id,
            'roll_number': record.student.roll_number,
            'new_status': record.status,
        })


class SubmitAttendanceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can submit attendance'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            teacher = Teacher.objects.get(user=request.user)
            session = Session.objects.get(
                id=session_id,
                teacher=teacher,
                is_active=False,
                is_submitted=False
            )
        except (Teacher.DoesNotExist, Session.DoesNotExist):
            return Response(
                {'error': 'Session not found or already submitted'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Lock the attendance
        session.is_submitted = True
        session.save()

        # Final summary
        records = AttendanceRecord.objects.filter(session=session)
        total_present = records.filter(status='present').count()
        total_absent = records.filter(status='absent').count()

        return Response({
            'message': 'Attendance submitted and locked successfully',
            'session_id': session.id,
            'total_present': total_present,
            'total_absent': total_absent,
        })
    
class MarkAttendanceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        print("DEBUG data:", request.data)
        # Step 1: Only students can mark attendance
        if request.user.role != 'student':
            return Response(
                {'error': 'Only students can mark attendance'},
                status=status.HTTP_403_FORBIDDEN
            )

        # Step 2: Get student record
        try:
            student = Student.objects.get(user=request.user)
        except Student.DoesNotExist:
            return Response(
                {'error': 'Student record not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Step 3: Get device record
        try:
            device = Device.objects.get(student=student, is_active=True)
        except Device.DoesNotExist:
            return Response(
                {'error': 'No registered device found. Please enroll your device first.'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Step 4: Get data from request
        session_id = request.data.get('session_id')
        qr_token = request.data.get('qr_token')
        signature = request.data.get('signature')
        scan_timestamp = request.data.get('scan_timestamp')

        if not all([session_id, qr_token, signature, scan_timestamp]):
            return Response(
                {'error': 'session_id, qr_token and signature are required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 5: Get session and validate
        try:
            session = Session.objects.get(id=session_id)
        except Session.DoesNotExist:
            return Response(
                {'error': 'Session not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        # Step 6: Check session is active
        if not session.is_active:
            return Response(
                {'error': 'Session is no longer active. Teacher has stopped attendance.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 7: Check QR token is valid
        if session.qr_token != qr_token and session.previous_qr_token != qr_token:
            return Response(
                {'error': 'Invalid QR code. Please scan the latest QR.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 8: Check QR not expired at SCAN TIME (not submission time)
        scan_time = datetime.fromtimestamp(scan_timestamp / 1000, tz=pytz.UTC)
        if scan_time > session.expires_at:
            return Response(
                {'error': 'QR code had already expired when you scanned it.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 9: Check student is enrolled in this class
        is_enrolled = Enrollment.objects.filter(
            student=student,
            class_enrolled=session.class_ref
        ).exists()

        if not is_enrolled:
            return Response(
                {'error': 'You are not enrolled in this class.'},
                status=status.HTTP_403_FORBIDDEN
            )

        # Step 10: Check not already marked in this session
        already_marked = AttendanceRecord.objects.filter(
            session=session,
            student=student
        ).exists()

        if already_marked:
            return Response(
                {'error': 'Attendance already marked for this session.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 11: Verify cryptographic signature
        try:
            # Load public key — support both PEM and DER formats
            if device.public_key.startswith('-----'):
                # PEM format (testing via Postman)
                public_key = serialization.load_pem_public_key(
                    device.public_key.encode()
                )
            else:
                # DER format (Base64) from Android Keystore
                from cryptography.hazmat.primitives.serialization import load_der_public_key
                der_bytes = base64.b64decode(device.public_key)
                public_key = load_der_public_key(der_bytes)

            # The message that was signed = session_id:qr_token
            message = f"{session_id}:{qr_token}".encode()

            # Decode signature from base64
            signature_bytes = base64.b64decode(signature)

            # Verify signature
            public_key.verify(
                signature_bytes,
                message,
                padding.PKCS1v15(),
                hashes.SHA256()
            )

        except InvalidSignature:
            return Response(
                {'error': 'Invalid signature. Request did not come from registered device.'},
                status=status.HTTP_403_FORBIDDEN
            )
        except Exception as e:
            return Response(
                {'error': f'Signature verification failed: {str(e)}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # Step 12: All checks passed — mark attendance
        record = AttendanceRecord.objects.create(
            session=session,
            student=student,
            device=device,
            status='present',
            signature=signature
        )

        return Response({
            'message': 'Attendance marked successfully',
            'roll_number': student.roll_number,
            'name': request.user.get_full_name(),
            'class_name': session.class_ref.name,
            'subject': session.class_ref.subject,
            'timestamp': record.timestamp,
        }, status=status.HTTP_201_CREATED)

class TeacherClassesView(APIView):
    permission_classes = [IsAuthenticated]
    def get(self, request):
        if request.user.role != 'teacher':
            return Response(
                {'error': 'Only teachers can view their classes'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            teacher = Teacher.objects.get(user=request.user)
        except Teacher.DoesNotExist:
            return Response(
                {'error': 'Teacher not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        classes = Class.objects.filter(teacher=teacher)
        data = [
            {
                'id': cls.id,
                'name': cls.name,
                'subject': cls.subject,
            }
            for cls in classes
        ]

        return Response({'classes': data})
    
class StudentAttendanceHistoryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if request.user.role != 'student':
            return Response(
                {'error': 'Only students can view their history'},
                status=status.HTTP_403_FORBIDDEN
            )

        try:
            student = Student.objects.get(user=request.user)
        except Student.DoesNotExist:
            return Response(
                {'error': 'Student not found'},
                status=status.HTTP_404_NOT_FOUND
            )

        records = AttendanceRecord.objects.filter(
            student=student
        ).select_related(
            'session__class_ref'
        ).order_by('-timestamp')

        data = [
            {
                'id': record.id,
                'class_name': record.session.class_ref.name,
                'subject': record.session.class_ref.subject,
                'status': record.status,
                'timestamp': format_timestamp(record.timestamp),
            }
            for record in records
        ]

        return Response({
            'records': data,
            'total': len(data),
        })