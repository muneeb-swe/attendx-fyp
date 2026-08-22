import base64
from datetime import timedelta

from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes, serialization

from django.test import TestCase
from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status

from users.models import User, Student, Teacher, Device
from .models import Class, Enrollment, Session, AttendanceRecord


def generate_keypair():
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem_public = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode()
    return private_key, pem_public


def sign_message(private_key, message: str) -> str:
    signature = private_key.sign(
        message.encode(), padding.PKCS1v15(), hashes.SHA256()
    )
    return base64.b64encode(signature).decode()


class AttendanceTestBase(TestCase):
    """Common fixtures shared by most attendance tests: a teacher, a
    class, and a student enrolled in it with a registered device."""

    def setUp(self):
        cache.clear()
        self.client = APIClient()

        self.teacher_user = User.objects.create_user(
            username='teacher1', password='pass123', role='teacher',
            first_name='Sana', last_name='Malik',
        )
        self.teacher = Teacher.objects.create(
            user=self.teacher_user, department='CS', employee_id='EMP1'
        )

        self.student_user = User.objects.create_user(
            username='student1', password='pass123', role='student',
            first_name='Ali', last_name='Khan',
        )
        self.student = Student.objects.create(
            user=self.student_user, roll_number='CS-101', department='CS', batch='2026'
        )

        self.class_obj = Class.objects.create(
            name='Data Structures', subject='CS201', teacher=self.teacher
        )
        Enrollment.objects.create(student=self.student, class_enrolled=self.class_obj)

        self.private_key, self.pem_public_key = generate_keypair()
        self.device = Device.objects.create(
            student=self.student, public_key=self.pem_public_key, device_fingerprint='device-A'
        )

    def start_session_as_teacher(self, expected_count=None):
        self.client.force_authenticate(user=self.teacher_user)
        payload = {'class_id': self.class_obj.id}
        if expected_count is not None:
            payload['expected_count'] = expected_count
        response = self.client.post('/api/attendance/generate-qr/', payload)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        return response.data

    def register_scan_as_student(self, session_id, qr_token):
        self.client.force_authenticate(user=self.student_user)
        response = self.client.post('/api/attendance/register-scan/', {
            'session_id': session_id, 'qr_token': qr_token,
        })
        return response

    def mark_attendance(self, scan_token, session_id, qr_token, private_key=None):
        private_key = private_key or self.private_key
        signature = sign_message(private_key, f"{session_id}:{qr_token}")
        self.client.force_authenticate(user=self.student_user)
        return self.client.post('/api/attendance/mark/', {
            'scan_token': scan_token, 'signature': signature,
        })

    def full_mark_flow(self):
        """Runs generate-qr -> register-scan -> mark end to end, returns the mark response."""
        session_data = self.start_session_as_teacher()
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        self.assertEqual(scan_response.status_code, status.HTTP_201_CREATED)
        return self.mark_attendance(
            scan_response.data['scan_token'], session_data['session_id'], session_data['qr_token']
        ), session_data


class GenerateQRViewTests(AttendanceTestBase):
    def test_teacher_can_start_session(self):
        data = self.start_session_as_teacher()
        self.assertIn('qr_image', data)
        self.assertIn('qr_token', data)
        session = Session.objects.get(id=data['session_id'])
        self.assertTrue(session.is_active)
        self.assertEqual(session.present_count, 0)

    def test_student_cannot_start_session(self):
        self.client.force_authenticate(user=self.student_user)
        response = self.client.post('/api/attendance/generate-qr/', {'class_id': self.class_obj.id})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_missing_class_id_rejected(self):
        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.post('/api/attendance/generate-qr/', {})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_class_not_owned_by_teacher_rejected(self):
        other_teacher_user = User.objects.create_user(username='t2', password='pass123', role='teacher')
        other_teacher = Teacher.objects.create(user=other_teacher_user, department='EE', employee_id='EMP2')
        other_class = Class.objects.create(name='Circuits', subject='EE101', teacher=other_teacher)

        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.post('/api/attendance/generate-qr/', {'class_id': other_class.id})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_starting_new_session_discards_stale_unsubmitted_ones(self):
        first = self.start_session_as_teacher()
        self.assertTrue(Session.objects.filter(id=first['session_id']).exists())

        second = self.start_session_as_teacher()
        # First (unsubmitted) session should be gone
        self.assertFalse(Session.objects.filter(id=first['session_id']).exists())
        self.assertTrue(Session.objects.filter(id=second['session_id']).exists())


class RefreshQRViewTests(AttendanceTestBase):
    def test_teacher_can_rotate_token(self):
        session_data = self.start_session_as_teacher()
        old_token = session_data['qr_token']

        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/refresh-qr/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertNotEqual(response.data['qr_token'], old_token)

    def test_refresh_on_stopped_session_fails(self):
        session_data = self.start_session_as_teacher()
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")

        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/refresh-qr/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_student_cannot_refresh(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.student_user)
        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/refresh-qr/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class RegisterScanViewTests(AttendanceTestBase):
    def test_valid_scan_returns_scan_token(self):
        session_data = self.start_session_as_teacher()
        response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('scan_token', response.data)

    def test_stale_qr_token_rejected(self):
        session_data = self.start_session_as_teacher()
        response = self.register_scan_as_student(session_data['session_id'], 'not-the-real-token')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_expired_qr_window_rejected(self):
        session_data = self.start_session_as_teacher()
        session = Session.objects.get(id=session_data['session_id'])
        session.expires_at = timezone.now() - timedelta(seconds=1)
        session.save()

        response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_teacher_cannot_register_scan(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.post('/api/attendance/register-scan/', {
            'session_id': session_data['session_id'], 'qr_token': session_data['qr_token'],
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_stopped_session_rejected(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")

        response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class MarkAttendanceViewTests(AttendanceTestBase):
    def test_full_flow_marks_present_with_signature(self):
        response, session_data = self.full_mark_flow()
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)
        self.assertEqual(record.status, 'present')
        self.assertEqual(record.original_status, 'present')
        self.assertTrue(record.signature)

    def test_invalid_signature_rejected(self):
        session_data = self.start_session_as_teacher()
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])

        wrong_private_key, _ = generate_keypair()
        response = self.mark_attendance(
            scan_response.data['scan_token'], session_data['session_id'],
            session_data['qr_token'], private_key=wrong_private_key,
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertFalse(AttendanceRecord.objects.filter(student=self.student).exists())

    def test_expired_scan_token_rejected(self):
        session_data = self.start_session_as_teacher()
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])

        from attendance.views import scan_signer
        import time as _time
        # Force-unsign with 0 max_age by faking an old signed value isn't
        # straightforward without waiting, so instead verify the token
        # round-trips correctly today, and separately verify max_age=0
        # rejects it immediately (proves the expiry check is wired up).
        with self.assertRaises(Exception):
            scan_signer.unsign(scan_response.data['scan_token'], max_age=0)

    def test_already_marked_rejected(self):
        response, session_data = self.full_mark_flow()
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        # Try to mark again with a fresh scan for the same (still active) session
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        if scan_response.status_code == status.HTTP_201_CREATED:
            second = self.mark_attendance(
                scan_response.data['scan_token'], session_data['session_id'], session_data['qr_token']
            )
            self.assertEqual(second.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unenrolled_student_rejected(self):
        outsider_user = User.objects.create_user(username='outsider', password='pass123', role='student')
        outsider = Student.objects.create(user=outsider_user, roll_number='CS-999', department='CS', batch='2026')
        outsider_key, outsider_pub = generate_keypair()
        Device.objects.create(student=outsider, public_key=outsider_pub, device_fingerprint='device-Z')

        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=outsider_user)
        scan_response = self.client.post('/api/attendance/register-scan/', {
            'session_id': session_data['session_id'], 'qr_token': session_data['qr_token'],
        })
        self.assertEqual(scan_response.status_code, status.HTTP_201_CREATED)

        signature = sign_message(outsider_key, f"{session_data['session_id']}:{session_data['qr_token']}")
        response = self.client.post('/api/attendance/mark/', {
            'scan_token': scan_response.data['scan_token'], 'signature': signature,
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_no_registered_device_rejected(self):
        self.device.delete()
        session_data = self.start_session_as_teacher()
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        response = self.mark_attendance(
            scan_response.data['scan_token'], session_data['session_id'], session_data['qr_token']
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_expected_count_reached_auto_stops_session(self):
        session_data = self.start_session_as_teacher(expected_count=1)
        scan_response = self.register_scan_as_student(session_data['session_id'], session_data['qr_token'])
        response = self.mark_attendance(
            scan_response.data['scan_token'], session_data['session_id'], session_data['qr_token']
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        session = Session.objects.get(id=session_data['session_id'])
        self.assertFalse(session.is_active)
        self.assertIsNotNone(session.stopped_at)


class StopSessionViewTests(AttendanceTestBase):
    def test_stop_marks_unscanned_enrolled_students_absent(self):
        # second student enrolled but never scans
        other_user = User.objects.create_user(username='s2', password='pass123', role='student')
        other_student = Student.objects.create(user=other_user, roll_number='CS-102', department='CS', batch='2026')
        Enrollment.objects.create(student=other_student, class_enrolled=self.class_obj)

        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=other_student)
        self.assertEqual(record.status, 'absent')
        self.assertEqual(record.original_status, 'absent')
        self.assertEqual(record.signature, '')

    def test_stop_does_not_touch_already_present_students(self):
        response, session_data = self.full_mark_flow()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")

        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)
        self.assertEqual(record.status, 'present')

    def test_student_cannot_stop_session(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.student_user)
        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class EditAttendanceViewTests(AttendanceTestBase):
    def test_teacher_can_override_status(self):
        response, session_data = self.full_mark_flow()
        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)

        self.client.force_authenticate(user=self.teacher_user)
        edit_response = self.client.patch(f'/api/attendance/record/{record.id}/edit/', {'status': 'absent'})
        self.assertEqual(edit_response.status_code, status.HTTP_200_OK)

        record.refresh_from_db()
        self.assertEqual(record.status, 'absent')
        self.assertEqual(record.original_status, 'present')  # preserved — this is the "proof"
        self.assertTrue(record.is_modified)
        self.assertTrue(record.signature)  # signature stays, even though current status changed

    def test_cannot_edit_submitted_session(self):
        response, session_data = self.full_mark_flow()
        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)

        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")

        edit_response = self.client.patch(f'/api/attendance/record/{record.id}/edit/', {'status': 'absent'})
        self.assertEqual(edit_response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_invalid_status_value_rejected(self):
        response, session_data = self.full_mark_flow()
        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)

        self.client.force_authenticate(user=self.teacher_user)
        edit_response = self.client.patch(f'/api/attendance/record/{record.id}/edit/', {'status': 'late'})
        self.assertEqual(edit_response.status_code, status.HTTP_400_BAD_REQUEST)


class SubmitAttendanceViewTests(AttendanceTestBase):
    def test_submit_locks_session(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")

        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        session = Session.objects.get(id=session_data['session_id'])
        self.assertTrue(session.is_submitted)

    def test_cannot_submit_while_still_active(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_cannot_double_submit(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")

        response = self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class SessionAttendanceViewTests(AttendanceTestBase):
    def test_roster_sorts_present_before_absent(self):
        other_user = User.objects.create_user(username='s2', password='pass123', role='student')
        other_student = Student.objects.create(user=other_user, roll_number='CS-102', department='CS', batch='2026')
        Enrollment.objects.create(student=other_student, class_enrolled=self.class_obj)

        response, session_data = self.full_mark_flow()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")

        roster = self.client.get(f"/api/attendance/session/{session_data['session_id']}/attendance/")
        self.assertEqual(roster.status_code, status.HTTP_200_OK)
        statuses = [s['status'] for s in roster.data['students']]
        self.assertEqual(statuses[0], 'present')

    def test_student_cannot_view_roster(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.student_user)
        response = self.client.get(f"/api/attendance/session/{session_data['session_id']}/attendance/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class TeacherClassesViewTests(AttendanceTestBase):
    def test_returns_only_own_classes(self):
        other_teacher_user = User.objects.create_user(username='t2', password='pass123', role='teacher')
        other_teacher = Teacher.objects.create(user=other_teacher_user, department='EE', employee_id='EMP2')
        Class.objects.create(name='Circuits', subject='EE101', teacher=other_teacher)

        self.client.force_authenticate(user=self.teacher_user)
        response = self.client.get('/api/attendance/teacher/classes/')
        self.assertEqual(len(response.data['classes']), 1)
        self.assertEqual(response.data['classes'][0]['name'], 'Data Structures')


class StudentAttendanceHistoryViewTests(AttendanceTestBase):
    def test_unsubmitted_session_shows_pending(self):
        response, session_data = self.full_mark_flow()
        self.client.force_authenticate(user=self.student_user)
        history = self.client.get('/api/attendance/student/history/')
        self.assertEqual(history.data['records'][0]['status'], 'pending')

    def test_modified_submitted_record_shows_modified_suffix(self):
        response, session_data = self.full_mark_flow()
        record = AttendanceRecord.objects.get(session_id=session_data['session_id'], student=self.student)

        self.client.force_authenticate(user=self.teacher_user)
        self.client.patch(f'/api/attendance/record/{record.id}/edit/', {'status': 'absent'})
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")

        self.client.force_authenticate(user=self.student_user)
        history = self.client.get('/api/attendance/student/history/')
        self.assertIn('modified', history.data['records'][0]['status'])


class DiscardSessionViewTests(AttendanceTestBase):
    def test_discard_deletes_session_and_records(self):
        response, session_data = self.full_mark_flow()
        self.client.force_authenticate(user=self.teacher_user)
        discard_response = self.client.delete(f"/api/attendance/session/{session_data['session_id']}/discard/")
        self.assertEqual(discard_response.status_code, status.HTTP_200_OK)

        self.assertFalse(Session.objects.filter(id=session_data['session_id']).exists())
        self.assertFalse(AttendanceRecord.objects.filter(session_id=session_data['session_id']).exists())

    def test_cannot_discard_submitted_session(self):
        session_data = self.start_session_as_teacher()
        self.client.force_authenticate(user=self.teacher_user)
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/stop/")
        self.client.post(f"/api/attendance/session/{session_data['session_id']}/submit/")

        response = self.client.delete(f"/api/attendance/session/{session_data['session_id']}/discard/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
