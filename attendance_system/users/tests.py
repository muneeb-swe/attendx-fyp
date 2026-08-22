import base64
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status

from .models import User, Student, Teacher, Device, DeviceEvent


def make_public_key_pem():
    """Generates a throwaway RSA public key in PEM format for enrollment tests."""
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return pem.decode()


class LoginViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='student1', password='pass123', role='student',
            first_name='Ali', last_name='Khan',
        )
        self.student = Student.objects.create(
            user=self.user, roll_number='CS-101', department='CS', batch='2026'
        )

    def test_login_success_returns_tokens_and_role(self):
        response = self.client.post('/api/auth/login/', {
            'username': 'student1', 'password': 'pass123',
        })
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access_token', response.data)
        self.assertIn('refresh_token', response.data)
        self.assertEqual(response.data['role'], 'student')
        self.assertEqual(response.data['roll_number'], 'CS-101')

    def test_login_wrong_password_rejected(self):
        response = self.client.post('/api/auth/login/', {
            'username': 'student1', 'password': 'wrongpass',
        })
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_nonexistent_user_rejected(self):
        response = self.client.post('/api/auth/login/', {
            'username': 'ghost', 'password': 'whatever',
        })
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_login_missing_fields_rejected(self):
        response = self.client.post('/api/auth/login/', {'username': 'student1'})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class DeviceEnrollViewTests(TestCase):
    """
    Covers every branch of DeviceEnrollView, including the DeviceEvent
    audit logging added alongside the admin dashboard, and the
    disabled-device re-enrollment bug fixed in serializers.py.
    """

    def setUp(self):
        self.client = APIClient()

        self.user1 = User.objects.create_user(username='s1', password='pass123', role='student')
        self.student1 = Student.objects.create(user=self.user1, roll_number='CS-101', department='CS', batch='2026')

        self.user2 = User.objects.create_user(username='s2', password='pass123', role='student')
        self.student2 = Student.objects.create(user=self.user2, roll_number='CS-102', department='CS', batch='2026')

        self.pem_key = make_public_key_pem()
        self.client.force_authenticate(user=self.user1)

    def test_first_enrollment_succeeds_and_logs_event(self):
        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'device-A',
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        device = Device.objects.get(student=self.student1)
        self.assertTrue(device.is_active)
        self.assertEqual(device.device_fingerprint, 'device-A')

        event = DeviceEvent.objects.get(student=self.student1)
        self.assertEqual(event.event_type, 'enrolled')

    def test_re_enrollment_same_fingerprint_succeeds_and_logs_event(self):
        Device.objects.create(student=self.student1, public_key='old-key', device_fingerprint='device-A')

        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'device-A',
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        self.assertEqual(Device.objects.filter(student=self.student1).count(), 1)

        event = DeviceEvent.objects.get(student=self.student1, event_type='re_enrolled')
        self.assertEqual(event.device_fingerprint, 'device-A')

    def test_enrolling_new_fingerprint_while_active_device_exists_is_blocked_and_logged(self):
        Device.objects.create(student=self.student1, public_key='old-key', device_fingerprint='device-A')

        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'device-B',
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

        event = DeviceEvent.objects.get(student=self.student1, event_type='mismatch_student_has_device')
        self.assertEqual(event.device_fingerprint, 'device-B')

    def test_enrolling_fingerprint_owned_by_another_student_is_blocked_and_logged(self):
        Device.objects.create(student=self.student2, public_key='key2', device_fingerprint='shared-fp')

        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'shared-fp',
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

        event = DeviceEvent.objects.get(student=self.student1, event_type='mismatch_fingerprint_taken')
        self.assertEqual(event.conflicting_student, self.student2)

    def test_invalid_public_key_format_rejected(self):
        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': 'not-a-real-key', 'device_fingerprint': 'device-A',
        })
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_teacher_cannot_enroll_device(self):
        teacher_user = User.objects.create_user(username='t1', password='pass123', role='teacher')
        Teacher.objects.create(user=teacher_user, department='CS', employee_id='EMP1')
        self.client.force_authenticate(user=teacher_user)

        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'device-A',
        })
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_disabled_device_does_not_block_new_enrollment(self):
        """
        Regression test for a real bug: DeviceEnrollSerializer.validate()
        used to check ALL devices ever created for a student, not just
        active ones. That meant once an admin disabled a lost device,
        the student could never enroll a replacement — defeating the
        entire point of disabling a device. Fixed in serializers.py to
        only check is_active=True.
        """
        Device.objects.create(
            student=self.student1, public_key='old-key',
            device_fingerprint='lost-phone', is_active=False,
        )

        response = self.client.post('/api/auth/device/enroll/', {
            'public_key': self.pem_key, 'device_fingerprint': 'new-phone',
        })
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        active_device = Device.objects.get(student=self.student1, is_active=True)
        self.assertEqual(active_device.device_fingerprint, 'new-phone')


class DeviceStatusViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user1 = User.objects.create_user(username='s1', password='pass123', role='student')
        self.student1 = Student.objects.create(user=self.user1, roll_number='CS-101', department='CS', batch='2026')
        self.user2 = User.objects.create_user(username='s2', password='pass123', role='student')
        self.student2 = Student.objects.create(user=self.user2, roll_number='CS-102', department='CS', batch='2026')
        self.client.force_authenticate(user=self.user1)

    def test_not_enrolled_when_no_device_exists(self):
        response = self.client.post('/api/auth/device/status/', {'device_fingerprint': 'device-A'})
        self.assertEqual(response.data['status'], 'not enrolled')
        self.assertFalse(response.data['enrolled'])

    def test_enrolled_when_fingerprint_matches_own_active_device(self):
        Device.objects.create(student=self.student1, public_key='key', device_fingerprint='device-A')
        response = self.client.post('/api/auth/device/status/', {'device_fingerprint': 'device-A'})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['enrolled'])

    def test_mismatch_when_fingerprint_belongs_to_another_student(self):
        Device.objects.create(student=self.student2, public_key='key', device_fingerprint='device-A')
        response = self.client.post('/api/auth/device/status/', {'device_fingerprint': 'device-A'})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['status'], 'device mismatch')

    def test_mismatch_when_student_has_a_different_active_device(self):
        Device.objects.create(student=self.student1, public_key='key', device_fingerprint='device-A')
        response = self.client.post('/api/auth/device/status/', {'device_fingerprint': 'device-B'})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['status'], 'device mismatch')


class DeviceConstraintTests(TestCase):
    """DB-level constraints, independent of any view."""

    def setUp(self):
        self.user1 = User.objects.create_user(username='s1', password='pass123', role='student')
        self.student1 = Student.objects.create(user=self.user1, roll_number='CS-101', department='CS', batch='2026')
        self.user2 = User.objects.create_user(username='s2', password='pass123', role='student')
        self.student2 = Student.objects.create(user=self.user2, roll_number='CS-102', department='CS', batch='2026')

    def test_one_active_device_per_student_enforced(self):
        Device.objects.create(student=self.student1, public_key='k1', device_fingerprint='fp1')
        from django.db import IntegrityError
        with self.assertRaises(IntegrityError):
            Device.objects.create(student=self.student1, public_key='k2', device_fingerprint='fp2')

    def test_disabled_devices_dont_count_toward_the_constraint(self):
        Device.objects.create(student=self.student1, public_key='k1', device_fingerprint='fp1', is_active=False)
        Device.objects.create(student=self.student1, public_key='k2', device_fingerprint='fp2', is_active=True)
        self.assertEqual(Device.objects.filter(student=self.student1, is_active=True).count(), 1)

    def test_one_active_fingerprint_across_students_enforced(self):
        Device.objects.create(student=self.student1, public_key='k1', device_fingerprint='shared-fp')
        from django.db import IntegrityError
        with self.assertRaises(IntegrityError):
            Device.objects.create(student=self.student2, public_key='k2', device_fingerprint='shared-fp')


class VerifyTokenViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(username='s1', password='pass123', role='student')

    def test_verify_with_valid_token(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.get('/api/auth/verify/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['valid'])

    def test_verify_without_authentication_rejected(self):
        response = self.client.get('/api/auth/verify/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
